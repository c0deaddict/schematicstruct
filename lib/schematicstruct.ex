defmodule SchematicStruct do
  @moduledoc """
  Based on https://github.com/saleyn/typedstruct
  """

  @accumulating_attrs [:ss_struct, :ss_types, :ss_enforce_keys, :ss_fields]

  import Schematic

  @doc false
  defmacro __using__(_) do
    quote do
      import Schematic
      import SchematicStruct, only: [schematic_struct: 1]

      def parse(data), do: SchematicStruct.parse(data, __MODULE__)
    end
  end

  def parse(data, module) do
    case Schematic.unify(module.schematic(), data) do
      {:error, err} -> {:error, {:parse_failed, err, data}}
      {:ok, struct} -> {:ok, struct}
    end
  end

  def neg_integer(), do: all([int(), raw(fn i -> i < 0 end, message: "must be <0")])
  def non_neg_integer(), do: all([int(), raw(fn i -> i >= 0 end, message: "must be >=0")])
  def pos_integer(), do: all([int(), raw(fn i -> i > 0 end, message: "must be >0")])

  @doc """
  Defines a schematic struct.

  Inside a `typedstruct` block, each field is defined through the `field/2`
  macro.

  ## Examples

      defmodule MyStruct do
        use SchematicStruct

        schematic_struct do
          field :field_one, String.t()
          field :field_two, integer(), nullable: true, json: "fieldTWO"
          field :field_three, String.t(), schema: oneof(["true", "false"])
          field :field_four, atom(), default: :hey
        end
      end
  """
  defmacro schematic_struct(do: block) do
    quote do
      Enum.each(unquote(@accumulating_attrs), fn attr ->
        Module.register_attribute(__MODULE__, attr, accumulate: true)
      end)

      import SchematicStruct
      unquote(block)

      @enforce_keys @ss_enforce_keys
      defstruct @ss_struct

      SchematicStruct.__struct_type__(@ss_types)

      SchematicStruct.__schematic__(@ss_fields)

      Enum.each(unquote(@accumulating_attrs), &Module.delete_attribute(__MODULE__, &1))
    end
  end

  @doc false
  defmacro __struct_type__(types) do
    quote bind_quoted: [types: types] do
      @type t() :: %__MODULE__{unquote_splicing(types)}
    end
  end

  @doc false
  defmacro __schematic__(fields) do
    quote bind_quoted: [fields: fields] do
      def schematic() do
        schema(__MODULE__, unquote({:%{}, [], fields}))
      end
    end
  end

  @doc """
  Defines a field in a schematic struct.

  ## Example

      # A field named :example of type String.t()
      field :example, String.t()

  ## Options

    * `default` - sets the default value for the field
    * `nullable` - if set to true, makes its type nullable
    * `json` - json key override, default is to convert from snake_case to camelCase
    * `schema` - schematic schema, default is derived from type (if possible)
  """
  defmacro field(name, type, opts \\ []) do
    opts = case Keyword.get(opts, :schema) do
      nil -> opts
      schema -> Keyword.put(opts, :schema, Macro.escape(schema))
    end

    quote bind_quoted: [name: name, type: Macro.escape(type), opts: opts] do
      SchematicStruct.__field__(name, type, opts, __ENV__)
    end
  end

  @doc false
  def __field__(name, type, opts, %Macro.Env{module: mod}) when is_atom(name) do
    if mod |> Module.get_attribute(:ss_struct) |> Keyword.has_key?(name) do
      raise ArgumentError, "the field #{inspect(name)} is already set"
    end

    has_default? = Keyword.has_key?(opts, :default)
    nullable? = Keyword.get(opts, :nullable, false)
    enforce? = not (has_default? or nullable?)

    Module.put_attribute(mod, :ss_struct, {name, opts[:default]})
    Module.put_attribute(mod, :ss_types, {name, type_for(type, nullable?)})
    if enforce?, do: Module.put_attribute(mod, :ss_enforce_keys, name)

    json = Keyword.get_lazy(opts, :json, fn -> name |> to_string() |> Recase.to_camel() end)
    schema = Keyword.get_lazy(opts, :schema, fn -> derive_schema(type, nullable?) end)

    key = {json, name}

    key =
      if not enforce? do
        quote bind_quoted: [key: key] do
          optional(key)
        end
      else
        key
      end

    Module.put_attribute(mod, :ss_fields, {key, schema})
  end

  def __field__(name, _type, _opts, _env) do
    raise ArgumentError, "a field name must be an atom, got #{inspect(name)}"
  end

  defp type_for(type, false), do: type
  defp type_for(type, _), do: quote(do: unquote(type) | nil)

  defp derive_schema(type, nullable) do
    schema = derive_schema(type)
    if nullable, do: {:nullable, [], [schema]}, else: schema
  end

  # Literals
  defp derive_schema(v) when is_number(v) or is_boolean(v) or is_atom(v) or is_bitstring(v), do: v

  # Primitive types
  defp derive_schema({:atom, _, []}), do: quote(do: atom())
  defp derive_schema({:any, _, []}), do: quote(do: any())
  defp derive_schema({:boolean, _, []}), do: quote(do: bool())
  defp derive_schema({:float, _, []}), do: quote(do: float())
  defp derive_schema({:integer, _, []}), do: quote(do: int())
  defp derive_schema({:neg_integer, _, []}), do: quote(do: SchematicStruct.neg_integer())
  defp derive_schema({:non_neg_integer, _, []}), do: quote(do: SchematicStruct.non_neg_integer())
  defp derive_schema({:pos_integer, _, []}), do: quote(do: SchematicStruct.pos_integer())

  # String.t() => str()
  # Module.t() => Module.schematic()
  defp derive_schema({{:., _, [{:__aliases__, _, [module]}, :t]}, _, []}) when is_atom(module) do
    case module do
      :String -> quote do: str()
      :Date -> quote do: date()
      _ -> quote do: unquote({:__aliases__, [], [module]}).schematic()
    end
  end

  # [type] => list(type)
  # list(type) => list(type)
  defp derive_schema([type]), do: derive_list(type)
  defp derive_schema({:list, _, [type]}), do: derive_list(type)

  # a | b => oneof([a, b])
  defp derive_schema({:|, _, types}) do
    {:oneof, [], [Enum.map(types, &derive_schema/1)]}
  end

  # TBD: maybe don't auto convert this?
  # NOTE: this captures any unmatched type functions, as they are in AST: {:fun, [], []}
  # {a, b} => tuple([a, b])
  defp derive_schema(type) when is_tuple(type) do
    {:tuple, [], [type |> Tuple.to_list() |> Enum.map(&derive_schema/1)]}
  end

  defp derive_schema(type) do
    IO.inspect(type)
    quote do: any()
  end

  defp derive_list(type), do: {:list, [], [derive_schema(type)]}
end
