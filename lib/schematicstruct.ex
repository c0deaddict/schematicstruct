defmodule Schematicstruct do
  @moduledoc """
  Documentation for `Schematicstruct`.
  """

  @doc """
  Hello world.

  ## Examples

      iex> Schematicstruct.hello()
      :world

  """
  def hello do
    :world
  end

  defmodule Person do
    use TypedStruct

    typedstruct do
      field :name, String.t(), nullable: false
      field :age, non_neg_integer(), nullable: true
      field :happy?, boolean(), default: false
      field :phone, String.t()
      field :intlist, [integer() | float()]
      field :tuple, :ok | {:error, atom()}
    end
  end
end
