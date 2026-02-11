defmodule Irish.Group do
  @moduledoc """
  Struct representing a WhatsApp group, parsed from Baileys GroupMetadata.
  """

  defstruct [
    :id,
    :subject,
    :owner,
    :description,
    :creation,
    :size,
    announce: false,
    restrict: false,
    is_community: false,
    participants: []
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          subject: String.t() | nil,
          owner: String.t() | nil,
          description: String.t() | nil,
          creation: integer() | nil,
          size: integer() | nil,
          announce: boolean(),
          restrict: boolean(),
          is_community: boolean(),
          participants: [Irish.Group.Participant.t()]
        }

  @doc "Build a Group struct from a raw Baileys GroupMetadata map."
  @spec from_raw(map()) :: t()
  def from_raw(data) when is_map(data) do
    alias Irish.Coerce

    %__MODULE__{
      id: data["id"],
      subject: data["subject"],
      owner: data["owner"],
      description: data["desc"],
      creation: Coerce.int(data["creation"]),
      size: Coerce.non_neg_int(data["size"]),
      announce: Coerce.bool(data["announce"]),
      restrict: Coerce.bool(data["restrict"]),
      is_community: Coerce.bool(data["isCommunity"]),
      participants: parse_participants(data["participants"])
    }
  end

  defp parse_participants(nil), do: []
  defp parse_participants(list) when is_list(list), do: Enum.map(list, &Irish.Group.Participant.from_raw/1)
end
