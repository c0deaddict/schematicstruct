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

  test "nested", %{mod: mod} do
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
        field(:name, String.t(), nullable: false)
        field(:age, non_neg_integer(), nullable: true)
        field(:happy?, boolean(), default: false)
        field(:phone, String.t())
        field(:intlist, [integer() | float()])
        field(:tuple, :ok | {:error, atom()})
        field(:nested, Sub.t())
      end
    end
    """

    sub = String.to_atom("#{mod}.Sub")
    assert [{^sub, _}, {^mod, _}] = Code.compile_string(code)

    assert {:ok, _} =
             mod.parse(%{
               "happy" => true,
               "name" => "test",
               "phone" => "woei",
               "age" => 123,
               "intlist" => [1, 3, 4, 5],
               "enum" => 123,
               "tuple" => {:error, :test},
               "nested" => %{"first" => 123}
             })
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
end
