defmodule SchematicStructTest do
  use ExUnit.Case
  import Schematic
  doctest SchematicStruct

  defp purge(mod) do
    :code.delete(mod)
    :code.purge(mod)
  end

  setup do
    # https://github.com/hauleth/ecto_function/blob/master/test/ecto_function_test.exs
    mod = String.to_atom("Elixir.Test#{System.unique_integer([:positive])}")

    on_exit(fn -> purge(Example) end)

    {:ok, mod: mod}
  end

  test "field names must be unique", %{mod: mod} do
    code = """
    defmodule :'#{mod}'do
      use SchematicStruct

      schematic_struct do
        field(:first, String.t())
        field(:first, integer())
      end
    end
    """

    assert_raise ArgumentError,
                 "the field :first is already set",
                 fn ->
                   Code.compile_string(code)
                 end
  end

  test "first", %{mod: mod} do
    code = """
    defmodule :'#{mod}' do
      use SchematicStruct

      schematic_struct do
        field(:first, String.t(), nullable: false)
        field(:second, integer())
      end
    end
    """

    assert [{^mod, _}] = Code.compile_string(code)
    assert {:ok, _} = mod.parse(%{"first" => "str", "second" => 123})
  end

  test "explicit schema", %{mod: mod} do
    code = """
    defmodule :'#{mod}' do
      use SchematicStruct

      schematic_struct do
        field(:custom, String.t(), schema: oneof(["a", "b"]))
      end
    end
    """

    assert [{^mod, _}] = Code.compile_string(code)
    assert {:ok, _} = mod.parse(%{"custom" => "a"})
    errors = %{"custom" => "expected either \"a\" or \"b\""}
    assert {:error, {:parse_failed, ^errors, _}} = mod.parse(%{"custom" => 123})
    assert {:error, {:parse_failed, ^errors, _}} = mod.parse(%{"custom" => "c"})
  end

  test "non-nullable fields without a default are not optional", %{mod: mod} do
    code = """
    defmodule :'#{mod}' do
      use SchematicStruct

      schematic_struct do
        field(:first, integer())
      end
    end
    """

    assert [{^mod, _}] = Code.compile_string(code)
    assert {:error, {:parse_failed, %{"first" => "is missing"}, %{}}} = mod.parse(%{})
  end

  test "nullable fields are optional", %{mod: mod} do
    code = """
    defmodule :'#{mod}' do
      use SchematicStruct

      schematic_struct do
        field(:first, integer(), nullable: true)
      end
    end
    """

    assert [{^mod, _}] = Code.compile_string(code)
    assert {:ok, s} = mod.parse(%{})
    assert s.first == nil
  end

  test "fields with a default are optional", %{mod: mod} do
    code = """
    defmodule :'#{mod}' do
      use SchematicStruct

      schematic_struct do
        field(:first, integer(), default: 0)
      end
    end
    """

    assert [{^mod, _}] = Code.compile_string(code)
    assert {:ok, s} = mod.parse(%{})
    assert s.first == 0
  end

  test "literal field types", %{mod: mod} do
    code = """
    defmodule :'#{mod}' do
      use SchematicStruct

      schematic_struct do
        field(:atom, :atom)
        field(:boolean, true)
        field(:number, 1)
        field(:null, nil)
      end
    end
    """

    assert [{^mod, _}] = Code.compile_string(code)

    assert mod.schematic() ==
             schema(mod, %{
               {"atom", :atom} => :atom,
               {"boolean", :boolean} => true,
               {"number", :number} => 1,
               {"null", :null} => nil
             })
  end

  test "primitive field types", %{mod: mod} do
    code = """
    defmodule :'#{mod}' do
      use SchematicStruct

      schematic_struct do
        field(:atom, atom())
        field(:any, any())
        field(:boolean, boolean())
        field(:float, float())
        field(:integer, integer())
        field(:neg_integer, neg_integer())
        field(:non_neg_integer, non_neg_integer())
        field(:pos_integer, pos_integer())
        field(:string, String.t())
        field(:number, number())
      end
    end
    """

    assert [{^mod, _}] = Code.compile_string(code)

    assert mod.schematic() ==
             schema(mod, %{
               {"any", :any} => any(),
               {"atom", :atom} => atom(),
               {"boolean", :boolean} => bool(),
               {"float", :float} => float(),
               {"integer", :integer} => int(),
               {"neg_integer", :neg_integer} => SchematicStruct.neg_integer(),
               {"non_neg_integer", :non_neg_integer} => SchematicStruct.non_neg_integer(),
               {"pos_integer", :pos_integer} => SchematicStruct.pos_integer(),
               {"string", :string} => str(),
               {"number", :number} => oneof([int(), float()])
             })
  end

  test "composite field types", %{mod: mod} do
    code = """
    defmodule :'#{mod}' do
      use SchematicStruct

      schematic_struct do
        field(:list, [integer()])
        field(:list_explicit, list(integer()))
        field(:oneof, :a | :b)
      end
    end
    """

    assert [{^mod, _}] = Code.compile_string(code)

    assert mod.schematic() ==
             schema(mod, %{
               {"list", :list} => list(int()),
               {"list_explicit", :list_explicit} => list(int()),
               {"oneof", :oneof} => oneof([:a, :b])
             })
  end

  test "tuples are not automatically translated", %{mod: mod} do
    code = """
    defmodule :'#{mod}' do
      use SchematicStruct

      schematic_struct do
        field(:first, {integer(), integer()})
        field(:second, {integer(), integer()}, schema: tuple([int(), int()]))
      end
    end
    """

    assert [{^mod, _}] = Code.compile_string(code)

    assert mod.schematic() ==
             schema(mod, %{
               {"first", :first} => any(),
               {"second", :second} => tuple([int(), int()])
             })
  end

  test "nested field type", %{mod: mod} do
    code = """
    defmodule :'#{mod}' do
      use SchematicStruct

      defmodule Sub do
        use SchematicStruct

        schematic_struct do
          field(:first, integer())
        end
      end

      schematic_struct do
        field(:nested, Sub.t())
      end
    end
    """

    sub = String.to_atom("#{mod}.Sub")
    assert [{^sub, _}, {^mod, _}] = Code.compile_string(code)

    assert mod.schematic() ==
             schema(mod, %{
               {"nested", :nested} => schema(sub, %{{"first", :first} => int()})
             })
  end

  test "nested with explicit module reference", %{mod: mod} do
    code = """
    defmodule :'#{mod}' do
      use SchematicStruct

      defmodule Sub do
        use SchematicStruct

        schematic_struct do
          field(:first, integer())
        end
      end

      schematic_struct do
        field(:nested, __MODULE__.Sub.t())
      end
    end
    """

    sub = String.to_atom("#{mod}.Sub")
    assert [{^sub, _}, {^mod, _}] = Code.compile_string(code)

    assert mod.schematic() ==
             schema(mod, %{
               {"nested", :nested} => schema(sub, %{{"first", :first} => int()})
             })
  end

  test "map of key_type and value_type", %{mod: mod} do
    code = """
    defmodule :'#{mod}' do
      use SchematicStruct

      schematic_struct do
        field(:first, %{integer() => String.t()})
      end
    end
    """

    assert [{^mod, _}] = Code.compile_string(code)

    assert mod.schematic() ==
             schema(mod, %{
               {"first", :first} => map(keys: int(), values: str())
             })
  end

  test "map type", %{mod: mod} do
    code = """
    defmodule :'#{mod}' do
      use SchematicStruct

      schematic_struct do
        field(:first, %{})
      end
    end
    """

    assert [{^mod, _}] = Code.compile_string(code)

    assert mod.schematic() == schema(mod, %{{"first", :first} => map()})
  end

  test "custom transform function", %{mod: mod} do
    code = """
    defmodule :'#{mod}' do
      use SchematicStruct, transform: &(&1 |> to_string() |> String.upcase())

      schematic_struct do
        field(:first, integer())
      end
    end
    """

    assert [{^mod, _}] = Code.compile_string(code)

    assert mod.schematic() ==
             schema(mod, %{
               {"FIRST", :first} => int()
             })
  end

  test "custom type rules", %{mod: mod} do
    code = """
    defmodule :"#{mod}" do
      use SchematicStruct,
        type_match: fn
          {:custom, _, []} -> quote(do: int())
          _ -> quote(do: any())
        end

      @type custom :: integer()

      schematic_struct do
        field(:first, custom())
      end
    end
    """

    assert [{^mod, _}] = Code.compile_string(code)

    assert mod.schematic() ==
             schema(mod, %{
               {"first", :first} => int()
             })
  end

  test "unrecognized types have schema any", %{mod: mod} do
    code = """
    defmodule :'#{mod}'do
      use SchematicStruct

      @type custom :: integer()

      schematic_struct do
        field(:first, custom())
      end
    end
    """

    assert [{^mod, _}] = Code.compile_string(code)

    assert mod.schematic() ==
             schema(mod, %{
               {"first", :first} => any()
             })
  end

  test "raise exception on unrecognized type", %{mod: mod} do
    code = """
    defmodule :'#{mod}'do
      use SchematicStruct,
        type_match: fn
          type -> raise "undefined type in schematic_struct: \#{inspect(type)}"
        end

      @type custom :: integer()

      schematic_struct do
        field(:first, custom())
      end
    end
    """

    assert_raise RuntimeError,
                 "undefined type in schematic_struct: {:custom, [line: 10, column: 19], []}",
                 fn ->
                   Code.compile_string(code)
                 end
  end

  test "integer range", %{mod: mod} do
    code = """
    defmodule :'#{mod}'do
      use SchematicStruct

      schematic_struct do
        field(:first, 1..10)
      end
    end
    """

    assert [{^mod, _}] = Code.compile_string(code)

    assert mod.schematic() ==
             schema(mod, %{
               {"first", :first} => SchematicStruct.integer_range(1, 10)
             })

    assert {:ok, s} = mod.parse(%{"first" => 5})
    assert s.first == 5

    assert {:error, {:parse_failed, %{"first" => ["must be in range 1..10"]}, %{"first" => 11}}} =
             mod.parse(%{"first" => 11})
  end

  test "nil fields are omitted in dump by default", %{mod: mod} do
    code = """
    defmodule :'#{mod}' do
      use SchematicStruct

      schematic_struct do
        field(:first, integer())
        field(:second, integer(), nullable: true)
        field(:third, integer(), nullable: true, default: nil)
      end
    end
    """

    assert [{^mod, _}] = Code.compile_string(code)
    assert {:ok, s = %{first: 1, second: nil, third: nil}} = mod.parse(%{"first" => 1})
    assert {:ok, d = %{"first" => 1}} = mod.dump(s)
    assert Map.has_key?(d, "second") == false
    assert Map.has_key?(d, "third") == false
  end

  test "nil fields are included in dump by with option", %{mod: mod} do
    code = """
    defmodule :'#{mod}' do
      use SchematicStruct, dump_nullable: true

      schematic_struct do
        field(:first, integer())
        field(:second, integer(), nullable: true)
        field(:third, integer(), nullable: true, default: nil)
      end
    end
    """

    assert [{^mod, _}] = Code.compile_string(code)
    assert {:ok, s = %{first: 1, second: nil, third: nil}} = mod.parse(%{"first" => 1})
    assert {:ok, %{"first" => 1, "second" => nil, "third" => nil}} = mod.dump(s)
  end

  test "parse_list with all valid elements", %{mod: mod} do
    code = """
    defmodule :'#{mod}' do
      use SchematicStruct

      schematic_struct do
        field(:first, integer())
      end
    end
    """

    assert [{^mod, _}] = Code.compile_string(code)
    assert {:ok, [%{first: 1}, %{first: 2}]} = mod.parse_list([%{"first" => 1}, %{"first" => 2}])
  end

  test "parse_list with invalid elements", %{mod: mod} do
    code = """
    defmodule :'#{mod}' do
      use SchematicStruct

      schematic_struct do
        field(:first, integer())
      end
    end
    """

    assert [{^mod, _}] = Code.compile_string(code)

    assert {:error, {:parse_failed, %{"first" => "expected an integer"}, %{"first" => nil}}} =
             mod.parse_list([%{"first" => nil}, %{"first" => nil}])
  end
end
