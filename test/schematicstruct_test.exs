defmodule SchematicStructTest do
  use ExUnit.Case
  doctest SchematicStruct

  # https://github.com/hauleth/ecto_function/blob/master/test/ecto_function_test.exs


  test "field names must be unique" do
    code = """
    defmodule Example do
      use SchematicStruct

      schematic_struct do
        field(:first, String.t())
        field(:first, integer())
      end
    end
    """

    assert_raise CompileError,
                 "the field :first is already set",
                 fn ->
                   Code.compile_string(code)
                 end
  end

  test "macro" do
    Macro.expand_once(defmodule Example do
      use SchematicStruct

      schematic_struct do
        field(:first, integer())
      end
    end, __ENV__
    )
  end

  test "first" do
    defmodule Example do
      use SchematicStruct

      schematic_struct do
        field(:first, String.t(), nullable: false)
        field(:second, integer())
      end
    end

    {:ok, _} = Example.parse(%{"first" => "str", "second" => 123})
  end

  test "nested" do
    defmodule Example do
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
        field(:custom, String.t(), schema: oneof(["a", "b"]))
      end
    end

    {:ok, example} =
      Example.parse(%{
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
end
