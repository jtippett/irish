defmodule Irish.Group.Participant do
  @moduledoc """
  Struct representing a participant in a WhatsApp group.
  """

  defstruct [:id, :phone_number, :admin]

  @type t :: %__MODULE__{
          id: String.t(),
          phone_number: String.t() | nil,
          admin: String.t() | nil
        }

  @doc "Build a Participant struct from a raw Baileys GroupParticipant map."
  @spec from_raw(map()) :: t()
  def from_raw(data) when is_map(data) do
    %__MODULE__{
      id: data["id"],
      phone_number: data["phoneNumber"],
      admin: data["admin"]
    }
  end
end
