defmodule TypedStruct do
  @accumulating_attrs [:ts_struct, :ts_types, :ts_enforce_keys, :ts_fields]

  @doc false
  defmacro __using__(_) do
    quote do
      import TypedStruct, only: [typedstruct: 1]
      import Schematic

      def parse(data), do: TypedStruct.parse(data, __MODULE__)
    end
  end

  def parse(data, module) do
    case Schematic.unify(module.schematic(), data) do
      {:error, err} -> {:error, {:parse_failed, err, data}}
      {:ok, struct} -> {:ok, struct}
    end
  end

  @doc """
  Defines a typed struct.

  Inside a `typedstruct` block, each field is defined through the `field/2`
  macro.

  ## Examples

      defmodule MyStruct do
        use TypedStruct

        typedstruct do
          field :field_one, String.t()
          field :field_two, integer(), nullable: true
          field :field_three, boolean(), nullable: true
          field :field_four, atom(), default: :hey
        end
      end
  """
  defmacro typedstruct(do: block) do
    ast = TypedStruct.__typedstruct__(block)

    quote do
      # Create a lexical scope.
      (fn -> unquote(ast) end).()
    end
  end

  @doc false
  def __typedstruct__(block) do
    quote do
      Enum.each(unquote(@accumulating_attrs), fn attr ->
        Module.register_attribute(__MODULE__, attr, accumulate: true)
      end)

      import TypedStruct
      unquote(block)

      @enforce_keys @ts_enforce_keys
      defstruct @ts_struct

      TypedStruct.__struct_type__(@ts_types)

      TypedStruct.__schematic__(@ts_fields)

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
  Defines a field in a typed struct.

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
    quote bind_quoted: [name: name, type: Macro.escape(type), opts: opts] do
      TypedStruct.__field__(name, type, opts, __ENV__)
    end
  end

  @doc false
  def __field__(name, type, opts, %Macro.Env{module: mod} = env) when is_atom(name) do
    if mod |> Module.get_attribute(:ts_struct) |> Keyword.has_key?(name) do
      raise ArgumentError, "the field #{inspect(name)} is already set"
    end

    has_default? = Keyword.has_key?(opts, :default)
    nullable? = Keyword.get(opts, :nullable, false)
    enforce? = not (has_default? or nullable?)

    Module.put_attribute(mod, :ts_struct, {name, opts[:default]})
    Module.put_attribute(mod, :ts_types, {name, type_for(type, nullable?)})
    if enforce?, do: Module.put_attribute(mod, :ts_enforce_keys, name)

    json = Keyword.get_lazy(opts, :json, fn () -> name |> to_string() |> Recase.to_camel() end)
    schema = Keyword.get_lazy(opts, :schema, fn () -> derive_schema(type, nullable?) end)

    # schema = quote(do: int())
    Module.put_attribute(mod, :ts_fields, {{json, name}, schema})
  end

  def __field__(name, _type, _opts, _env) do
    raise ArgumentError, "a field name must be an atom, got #{inspect(name)}"
  end

  # Makes the type nullable if the key is not enforced.
  defp type_for(type, false), do: type
  defp type_for(type, _), do: quote(do: unquote(type) | nil)

  defp derive_schema(type, nullable) do
    schema = derive_schema(type)
    if nullable, do: {:nullable, [], [schema]}, else: schema
  end

  defp derive_schema({:boolean, _, _}), do: quote do: bool()
  defp derive_schema({:non_neg_integer, _, _}), do: quote do: int()  # TODO: guarantee positive integer?
  defp derive_schema(type) do
    IO.inspect(type)
    quote do: int()
  end
end
