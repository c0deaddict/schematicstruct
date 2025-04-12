defmodule Example do
  use SchematicStruct

  schematic_struct do
    field :name, String.t(), nullable: false
    field :age, non_neg_integer(), nullable: true
    field :happy?, boolean(), default: false
    field :phone, String.t()
    field :intlist, [integer() | float()]
    field :tuple, :ok | {:error, atom()}
  end
end
