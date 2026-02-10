defmodule Irish.ContactTest do
  use ExUnit.Case

  alias Irish.Contact

  @raw_contact %{
    "id" => "1234567890@s.whatsapp.net",
    "lid" => "123456@lid",
    "phoneNumber" => "+1234567890",
    "name" => "Alice Smith",
    "notify" => "Alice",
    "verifiedName" => "Alice's Business",
    "imgUrl" => "https://example.com/img.jpg",
    "status" => "Hello there"
  }

  describe "from_raw/1" do
    test "parses all fields" do
      contact = Contact.from_raw(@raw_contact)

      assert %Contact{} = contact
      assert contact.id == "1234567890@s.whatsapp.net"
      assert contact.lid == "123456@lid"
      assert contact.phone_number == "+1234567890"
      assert contact.name == "Alice Smith"
      assert contact.notify == "Alice"
      assert contact.verified_name == "Alice's Business"
      assert contact.img_url == "https://example.com/img.jpg"
      assert contact.status == "Hello there"
    end

    test "handles missing optional fields" do
      contact = Contact.from_raw(%{"id" => "x@s.whatsapp.net"})

      assert contact.id == "x@s.whatsapp.net"
      assert contact.name == nil
      assert contact.notify == nil
    end
  end

  describe "display_name/1" do
    test "returns name first" do
      contact = Contact.from_raw(@raw_contact)
      assert Contact.display_name(contact) == "Alice Smith"
    end

    test "falls back to notify" do
      contact = Contact.from_raw(%{"notify" => "Alice", "verifiedName" => "Biz"})
      assert Contact.display_name(contact) == "Alice"
    end

    test "falls back to verified_name" do
      contact = Contact.from_raw(%{"verifiedName" => "Biz"})
      assert Contact.display_name(contact) == "Biz"
    end

    test "falls back to phone_number" do
      contact = Contact.from_raw(%{"phoneNumber" => "+1234567890"})
      assert Contact.display_name(contact) == "+1234567890"
    end

    test "falls back to id" do
      contact = Contact.from_raw(%{"id" => "x@s.whatsapp.net"})
      assert Contact.display_name(contact) == "x@s.whatsapp.net"
    end

    test "returns nil when all fields are nil" do
      contact = Contact.from_raw(%{})
      assert Contact.display_name(contact) == nil
    end
  end
end
