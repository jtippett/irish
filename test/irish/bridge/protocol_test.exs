defmodule Irish.Bridge.ProtocolTest do
  use ExUnit.Case, async: true

  alias Irish.Bridge.Protocol

  describe "encode_request/3" do
    test "encodes request envelope with version" do
      assert {:ok, json} = Protocol.encode_request("abc", "send_message", %{jid: "x"})
      decoded = Jason.decode!(json)
      assert decoded["v"] == 1
      assert decoded["id"] == "abc"
      assert decoded["cmd"] == "send_message"
      assert decoded["args"] == %{"jid" => "x"}
    end

    test "rejects non-binary id" do
      assert_raise FunctionClauseError, fn ->
        Protocol.encode_request(123, "cmd", %{})
      end
    end
  end

  describe "decode_line/1" do
    test "decodes valid v1 message" do
      line = Jason.encode!(%{v: 1, id: "abc", ok: true, data: %{status: "ok"}})
      assert {:ok, msg} = Protocol.decode_line(line)
      assert msg["v"] == 1
      assert msg["id"] == "abc"
    end

    test "defaults missing version to v1" do
      line = Jason.encode!(%{event: "connection.update", data: %{}})
      assert {:ok, msg} = Protocol.decode_line(line)
      assert msg["event"] == "connection.update"
    end

    test "rejects unsupported envelope versions" do
      line = Jason.encode!(%{v: 99, event: "connection.update", data: %{}})
      assert {:error, :unsupported_version} = Protocol.decode_line(line)
    end

    test "rejects invalid JSON" do
      assert {:error, :invalid_json} = Protocol.decode_line("not json{}")
    end
  end

  describe "encode_response/2" do
    test "encodes success response" do
      assert {:ok, json} = Protocol.encode_response("r1", {:ok, %{creds: "data"}})
      decoded = Jason.decode!(json)
      assert decoded["v"] == 1
      assert decoded["id"] == "r1"
      assert decoded["ok"] == true
      assert decoded["data"] == %{"creds" => "data"}
    end

    test "encodes error response" do
      assert {:ok, json} = Protocol.encode_response("r2", {:error, :not_found})
      decoded = Jason.decode!(json)
      assert decoded["v"] == 1
      assert decoded["id"] == "r2"
      assert decoded["ok"] == false
      assert decoded["error"] == "not_found"
    end
  end

  describe "message_type/1" do
    test "classifies bridge requests" do
      assert :request == Protocol.message_type(%{"req" => "auth.load_creds", "id" => "x"})
    end

    test "classifies command responses" do
      assert :response == Protocol.message_type(%{"ok" => true, "id" => "x", "data" => %{}})
    end

    test "classifies events" do
      assert :event == Protocol.message_type(%{"event" => "connection.update", "data" => %{}})
    end

    test "defaults unknown to event" do
      assert :event == Protocol.message_type(%{"something" => "else"})
    end
  end
end
