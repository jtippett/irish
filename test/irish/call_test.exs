defmodule Irish.CallTest do
  use ExUnit.Case

  alias Irish.Call

  @raw_call %{
    "chatId" => "1234567890@s.whatsapp.net",
    "from" => "9876543210@s.whatsapp.net",
    "isGroup" => false,
    "groupJid" => nil,
    "id" => "call123",
    "date" => 1_700_000_000,
    "isVideo" => true,
    "status" => "offer",
    "offline" => false,
    "latencyMs" => 150
  }

  describe "from_raw/1" do
    test "parses all fields" do
      call = Call.from_raw(@raw_call)

      assert %Call{} = call
      assert call.chat_id == "1234567890@s.whatsapp.net"
      assert call.from == "9876543210@s.whatsapp.net"
      assert call.is_group == false
      assert call.group_jid == nil
      assert call.id == "call123"
      assert call.date == 1_700_000_000
      assert call.is_video == true
      assert call.status == :offer
      assert call.offline == false
      assert call.latency_ms == 150
    end

    test "maps all status strings to atoms" do
      for {str, atom} <- [
            {"offer", :offer},
            {"ringing", :ringing},
            {"timeout", :timeout},
            {"reject", :reject},
            {"accept", :accept},
            {"terminate", :terminate}
          ] do
        call = Call.from_raw(%{"status" => str})
        assert call.status == atom
      end
    end

    test "handles missing fields with defaults" do
      call = Call.from_raw(%{})

      assert call.is_group == false
      assert call.is_video == false
      assert call.offline == false
      assert call.status == nil
    end

    test "coerces string date to integer" do
      call = Call.from_raw(%{"date" => "1700000000"})
      assert call.date == 1_700_000_000
    end

    test "coerces float latency to integer" do
      call = Call.from_raw(%{"latencyMs" => 150.7})
      assert call.latency_ms == 150
    end

    test "handles nil date" do
      call = Call.from_raw(%{"date" => nil})
      assert call.date == nil
    end
  end
end
