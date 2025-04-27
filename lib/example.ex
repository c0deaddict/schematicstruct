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

  def test() do
    example =
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
