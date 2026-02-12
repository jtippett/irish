defmodule Irish.MessageTest do
  use ExUnit.Case

  alias Irish.Message
  alias Irish.MessageKey

  @raw_message %{
    "key" => %{
      "remoteJid" => "1234567890@s.whatsapp.net",
      "fromMe" => false,
      "id" => "MSG001"
    },
    "message" => %{"conversation" => "Hello world"},
    "messageTimestamp" => 1_700_000_000,
    "status" => 2,
    "participant" => nil,
    "pushName" => "Alice",
    "broadcast" => false,
    "starred" => false
  }

  describe "from_raw/1" do
    test "parses all fields" do
      msg = Message.from_raw(@raw_message)

      assert %Message{} = msg
      assert %MessageKey{} = msg.key
      assert msg.key.remote_jid == "1234567890@s.whatsapp.net"
      assert msg.key.id == "MSG001"
      assert msg.message == %{"conversation" => "Hello world"}
      assert msg.message_timestamp == 1_700_000_000
      assert msg.status == :server_ack
      assert msg.push_name == "Alice"
      assert msg.broadcast == false
      assert msg.starred == false
    end

    test "coerces string timestamp to integer" do
      msg = Message.from_raw(%{"messageTimestamp" => "1700000000"})
      assert msg.message_timestamp == 1_700_000_000
    end

    test "handles nil key" do
      msg = Message.from_raw(%{"message" => %{"conversation" => "hi"}})
      assert msg.key == nil
    end

    test "maps all status codes" do
      for {code, atom} <- [
            {0, :error},
            {1, :pending},
            {2, :server_ack},
            {3, :delivery_ack},
            {4, :read},
            {5, :played}
          ] do
        msg = Message.from_raw(%{"status" => code})
        assert msg.status == atom
      end
    end

    test "handles starred and broadcast true" do
      msg = Message.from_raw(%{"starred" => true, "broadcast" => true})
      assert msg.starred == true
      assert msg.broadcast == true
    end

    test "parses message stub fields" do
      msg = Message.from_raw(%{"messageStubType" => 27, "messageStubParameters" => ["Alice"]})
      assert msg.message_stub_type == 27
      assert msg.message_stub_parameters == ["Alice"]
    end

    test "handles non-parseable timestamp" do
      msg = Message.from_raw(%{"messageTimestamp" => "not_a_number"})
      assert msg.message_timestamp == nil
    end

    test "handles nil timestamp" do
      msg = Message.from_raw(%{"messageTimestamp" => nil})
      assert msg.message_timestamp == nil
    end

    test "coerces float timestamp" do
      msg = Message.from_raw(%{"messageTimestamp" => 1_700_000_000.5})
      assert msg.message_timestamp == 1_700_000_000
    end

    test "coerces empty string participant to nil" do
      msg = Message.from_raw(%{"participant" => ""})
      assert msg.participant == nil
    end

    test "coerces string messageStubType" do
      msg = Message.from_raw(%{"messageStubType" => "27"})
      assert msg.message_stub_type == 27
    end

    test "handles unknown status code" do
      msg = Message.from_raw(%{"status" => 99})
      assert msg.status == nil
    end
  end

  describe "text/1" do
    test "extracts conversation text" do
      msg = Message.from_raw(%{"message" => %{"conversation" => "Hello"}})
      assert Message.text(msg) == "Hello"
    end

    test "extracts extendedTextMessage text" do
      msg =
        Message.from_raw(%{"message" => %{"extendedTextMessage" => %{"text" => "Quoted reply"}}})

      assert Message.text(msg) == "Quoted reply"
    end

    test "extracts image caption" do
      msg = Message.from_raw(%{"message" => %{"imageMessage" => %{"caption" => "Photo caption"}}})
      assert Message.text(msg) == "Photo caption"
    end

    test "extracts video caption" do
      msg = Message.from_raw(%{"message" => %{"videoMessage" => %{"caption" => "Video cap"}}})
      assert Message.text(msg) == "Video cap"
    end

    test "extracts document caption" do
      msg = Message.from_raw(%{"message" => %{"documentMessage" => %{"caption" => "Doc cap"}}})
      assert Message.text(msg) == "Doc cap"
    end

    test "returns nil for non-text messages" do
      msg = Message.from_raw(%{"message" => %{"stickerMessage" => %{}}})
      assert Message.text(msg) == nil
    end

    test "returns nil for nil message" do
      msg = Message.from_raw(%{})
      assert Message.text(msg) == nil
    end
  end

  describe "type/1" do
    test "detects conversation as :text" do
      msg = Message.from_raw(%{"message" => %{"conversation" => "hi"}})
      assert Message.type(msg) == :text
    end

    test "detects image" do
      msg = Message.from_raw(%{"message" => %{"imageMessage" => %{}}})
      assert Message.type(msg) == :image
    end

    test "detects video" do
      msg = Message.from_raw(%{"message" => %{"videoMessage" => %{}}})
      assert Message.type(msg) == :video
    end

    test "detects audio" do
      msg = Message.from_raw(%{"message" => %{"audioMessage" => %{}}})
      assert Message.type(msg) == :audio
    end

    test "detects sticker" do
      msg = Message.from_raw(%{"message" => %{"stickerMessage" => %{}}})
      assert Message.type(msg) == :sticker
    end

    test "detects document" do
      msg = Message.from_raw(%{"message" => %{"documentMessage" => %{}}})
      assert Message.type(msg) == :document
    end

    test "detects extendedTextMessage as :text" do
      msg = Message.from_raw(%{"message" => %{"extendedTextMessage" => %{"text" => "hi"}}})
      assert Message.type(msg) == :text
    end

    test "detects location" do
      msg = Message.from_raw(%{"message" => %{"locationMessage" => %{}}})
      assert Message.type(msg) == :location
    end

    test "detects live_location" do
      msg = Message.from_raw(%{"message" => %{"liveLocationMessage" => %{}}})
      assert Message.type(msg) == :live_location
    end

    test "detects contact" do
      msg = Message.from_raw(%{"message" => %{"contactMessage" => %{}}})
      assert Message.type(msg) == :contact
    end

    test "detects contacts array" do
      msg = Message.from_raw(%{"message" => %{"contactsArrayMessage" => %{}}})
      assert Message.type(msg) == :contacts
    end

    test "detects reaction" do
      msg = Message.from_raw(%{"message" => %{"reactionMessage" => %{}}})
      assert Message.type(msg) == :reaction
    end

    test "detects poll" do
      for key <- ["pollCreationMessage", "pollCreationMessageV2", "pollCreationMessageV3"] do
        msg = Message.from_raw(%{"message" => %{key => %{}}})
        assert Message.type(msg) == :poll, "expected :poll for #{key}"
      end
    end

    test "detects view_once" do
      for key <- ["viewOnceMessage", "viewOnceMessageV2"] do
        msg = Message.from_raw(%{"message" => %{key => %{}}})
        assert Message.type(msg) == :view_once, "expected :view_once for #{key}"
      end
    end

    test "detects ephemeral" do
      msg = Message.from_raw(%{"message" => %{"ephemeralMessage" => %{}}})
      assert Message.type(msg) == :ephemeral
    end

    test "detects edited" do
      msg = Message.from_raw(%{"message" => %{"editedMessage" => %{}}})
      assert Message.type(msg) == :edited
    end

    test "detects protocol" do
      msg = Message.from_raw(%{"message" => %{"protocolMessage" => %{}}})
      assert Message.type(msg) == :protocol
    end

    test "returns :unknown for nil message" do
      msg = Message.from_raw(%{})
      assert Message.type(msg) == :unknown
    end

    test "returns :unknown for unrecognized content" do
      msg = Message.from_raw(%{"message" => %{"someFutureType" => %{}}})
      assert Message.type(msg) == :unknown
    end
  end

  describe "media?/1" do
    test "true for image, video, audio, document, sticker" do
      for type_key <- [
            "imageMessage",
            "videoMessage",
            "audioMessage",
            "documentMessage",
            "stickerMessage"
          ] do
        msg = Message.from_raw(%{"message" => %{type_key => %{}}})
        assert Message.media?(msg), "expected media? for #{type_key}"
      end
    end

    test "false for text and reaction" do
      for type_key <- ["conversation", "reactionMessage"] do
        msg = Message.from_raw(%{"message" => %{type_key => "hi"}})
        refute Message.media?(msg), "expected not media? for #{type_key}"
      end
    end
  end

  describe "from/1" do
    test "returns participant when present on message" do
      msg =
        Message.from_raw(%{
          "key" => %{"remoteJid" => "group@g.us"},
          "participant" => "sender@s.whatsapp.net"
        })

      assert Message.from(msg) == "sender@s.whatsapp.net"
    end

    test "returns key participant for group messages" do
      msg =
        Message.from_raw(%{
          "key" => %{"remoteJid" => "group@g.us", "participant" => "sender@s.whatsapp.net"}
        })

      assert Message.from(msg) == "sender@s.whatsapp.net"
    end

    test "returns remote_jid for 1:1 messages" do
      msg =
        Message.from_raw(%{
          "key" => %{"remoteJid" => "user@s.whatsapp.net", "fromMe" => false, "id" => "x"}
        })

      assert Message.from(msg) == "user@s.whatsapp.net"
    end

    test "returns nil when no key" do
      msg = Message.from_raw(%{})
      assert Message.from(msg) == nil
    end
  end
end
