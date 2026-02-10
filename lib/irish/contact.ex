defmodule Irish.Contact do
  @moduledoc """
  Struct representing a WhatsApp contact.

  Received via `"contacts.upsert"` and `"contacts.update"` events. Partial
  updates may leave most fields `nil`.

  ## Fields

  | Field | Type | Description |
  |---|---|---|
  | `id` | `String.t()` | JID (`number@s.whatsapp.net`) |
  | `lid` | `String.t()` | Linked device ID |
  | `phone_number` | `String.t()` | Phone number string |
  | `name` | `String.t()` | Contact name from address book |
  | `notify` | `String.t()` | Push name set by the user |
  | `verified_name` | `String.t()` | WhatsApp Business verified name |
  | `img_url` | `String.t()` | Profile picture URL |
  | `status` | `String.t()` | About/status text |

  ## Examples

      contact = Irish.Contact.from_raw(%{"id" => "15551234567@s.whatsapp.net", "name" => "Alice"})
      Irish.Contact.display_name(contact)  #=> "Alice"
  """

  defstruct [:id, :lid, :phone_number, :name, :notify, :verified_name, :img_url, :status]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          lid: String.t() | nil,
          phone_number: String.t() | nil,
          name: String.t() | nil,
          notify: String.t() | nil,
          verified_name: String.t() | nil,
          img_url: String.t() | nil,
          status: String.t() | nil
        }

  @doc "Build a Contact from a raw Baileys contact map."
  @spec from_raw(map()) :: t()
  def from_raw(data) when is_map(data) do
    %__MODULE__{
      id: data["id"],
      lid: data["lid"],
      phone_number: data["phoneNumber"],
      name: data["name"],
      notify: data["notify"],
      verified_name: data["verifiedName"],
      img_url: data["imgUrl"],
      status: data["status"]
    }
  end

  @doc "Returns the best available display name for a contact."
  @spec display_name(t()) :: String.t() | nil
  def display_name(%__MODULE__{} = c) do
    c.name || c.notify || c.verified_name || c.phone_number || c.id
  end
end
