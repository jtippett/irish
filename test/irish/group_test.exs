defmodule Irish.GroupTest do
  use ExUnit.Case

  alias Irish.Group
  alias Irish.Group.Participant

  @raw_group %{
    "id" => "6592956594-1547190709@g.us",
    "subject" => "Zipmex Domain and Website",
    "owner" => "262096201719887@lid",
    "desc" => "Group for website stuff",
    "creation" => 1_547_190_709,
    "size" => 5,
    "announce" => false,
    "restrict" => false,
    "isCommunity" => false,
    "participants" => [
      %{"admin" => nil, "id" => "8074605666368@lid", "phoneNumber" => "66917439845@s.whatsapp.net"},
      %{
        "admin" => "superadmin",
        "id" => "262096201719887@lid",
        "phoneNumber" => "6592956594@s.whatsapp.net"
      }
    ]
  }

  describe "Group.from_raw/1" do
    test "parses all fields" do
      group = Group.from_raw(@raw_group)

      assert %Group{} = group
      assert group.id == "6592956594-1547190709@g.us"
      assert group.subject == "Zipmex Domain and Website"
      assert group.owner == "262096201719887@lid"
      assert group.description == "Group for website stuff"
      assert group.creation == 1_547_190_709
      assert group.size == 5
      assert group.announce == false
      assert group.restrict == false
      assert group.is_community == false
      assert length(group.participants) == 2
    end

    test "handles missing optional fields" do
      group = Group.from_raw(%{"id" => "test@g.us"})

      assert group.id == "test@g.us"
      assert group.subject == nil
      assert group.participants == []
      assert group.announce == false
    end

    test "coerces announce/restrict/isCommunity to boolean" do
      group = Group.from_raw(%{"id" => "x@g.us", "announce" => true, "restrict" => true, "isCommunity" => true})

      assert group.announce == true
      assert group.restrict == true
      assert group.is_community == true
    end
  end

  describe "Participant.from_raw/1" do
    test "parses participant fields" do
      p = Participant.from_raw(%{"id" => "123@lid", "phoneNumber" => "123@s.whatsapp.net", "admin" => "superadmin"})

      assert %Participant{} = p
      assert p.id == "123@lid"
      assert p.phone_number == "123@s.whatsapp.net"
      assert p.admin == "superadmin"
    end

    test "handles nil admin" do
      p = Participant.from_raw(%{"id" => "456@lid", "admin" => nil})

      assert p.admin == nil
      assert p.phone_number == nil
    end
  end

  describe "from_raw with nested participants" do
    test "participants are Participant structs" do
      group = Group.from_raw(@raw_group)
      [first, second] = group.participants

      assert %Participant{} = first
      assert first.admin == nil
      assert first.phone_number == "66917439845@s.whatsapp.net"

      assert %Participant{} = second
      assert second.admin == "superadmin"
    end
  end
end
