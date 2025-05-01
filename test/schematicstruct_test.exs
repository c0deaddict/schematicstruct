defmodule SchematicStructTest do
  use ExUnit.Case
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
    assert """
           schema(#{mod}, %{
             {"atom", :atom} => :atom,
             {"boolean", :boolean} => true,
             {"number", :number} => 1
           })
           """ == inspect(mod.schematic()) <> "\n"
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
    assert """
           schema(#{mod}, %{
             {"any", :any} => any(),
             {"atom", :atom} => atom(),
             {"boolean", :boolean} => bool(),
             {"float", :float} => float(),
             {"integer", :integer} => int(),
             {"negInteger", :neg_integer} => all([int(), raw("fn")]),
             {"nonNegInteger", :non_neg_integer} => all([int(), raw("fn")]),
             {"posInteger", :pos_integer} => all([int(), raw("fn")]),
             {"string", :string} => str()
           })
           """ == inspect(mod.schematic()) <> "\n"
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
    assert """
           schema(#{mod}, %{
             {"list", :list} => list(int()),
             {"listExplicit", :list_explicit} => list(int()),
             {"oneof", :oneof} => oneof([:a, :b])
           })
           """ == inspect(mod.schematic()) <> "\n"
  end
end
