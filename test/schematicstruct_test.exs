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
      end
    end
    """

    assert [{^mod, _}] = Code.compile_string(code)

    assert mod.schematic() ==
             schema(mod, %{
               {"atom", :atom} => :atom,
               {"boolean", :boolean} => true,
               {"number", :number} => 1
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
               {"negInteger", :neg_integer} => SchematicStruct.neg_integer(),
               {"nonNegInteger", :non_neg_integer} => SchematicStruct.non_neg_integer(),
               {"posInteger", :pos_integer} => SchematicStruct.pos_integer(),
               {"string", :string} => str()
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
               {"listExplicit", :list_explicit} => list(int()),
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

      alias __MODULE__.Sub

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
end
