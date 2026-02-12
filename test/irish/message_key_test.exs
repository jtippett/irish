defmodule Irish.MessageKeyTest do
  use ExUnit.Case

  alias Irish.MessageKey

  @raw_key %{
    "remoteJid" => "1234567890@s.whatsapp.net",
    "fromMe" => true,
    "id" => "ABCDEF123456",
    "participant" => "9876543210@s.whatsapp.net"
  }

  describe "from_raw/1" do
    test "parses all fields" do
      key = MessageKey.from_raw(@raw_key)

      assert %MessageKey{} = key
      assert key.remote_jid == "1234567890@s.whatsapp.net"
      assert key.from_me == true
      assert key.id == "ABCDEF123456"
      assert key.participant == "9876543210@s.whatsapp.net"
    end

    test "defaults from_me to false" do
      key = MessageKey.from_raw(%{"id" => "abc"})

      assert key.from_me == false
      assert key.remote_jid == nil
      assert key.participant == nil
    end

    test "coerces non-true fromMe to false" do
      key = MessageKey.from_raw(%{"fromMe" => nil, "id" => "x"})
      assert key.from_me == false
    end
  end

  describe "to_raw/1" do
    test "converts back to camelCase map" do
      key = MessageKey.from_raw(@raw_key)
      raw = MessageKey.to_raw(key)

      assert raw == %{
               "remoteJid" => "1234567890@s.whatsapp.net",
               "fromMe" => true,
               "id" => "ABCDEF123456",
               "participant" => "9876543210@s.whatsapp.net"
             }
    end

    test "omits participant when nil" do
      key =
        MessageKey.from_raw(%{
          "remoteJid" => "x@s.whatsapp.net",
          "fromMe" => false,
          "id" => "abc"
        })

      raw = MessageKey.to_raw(key)

      assert raw == %{"remoteJid" => "x@s.whatsapp.net", "fromMe" => false, "id" => "abc"}
      refute Map.has_key?(raw, "participant")
    end

    test "round-trips from_raw -> to_raw" do
      raw = MessageKey.from_raw(@raw_key) |> MessageKey.to_raw()
      assert raw == @raw_key
    end
  end
end
