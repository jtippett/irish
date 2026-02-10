defmodule Irish.Bridge.Protocol do
  @moduledoc """
  Versioned JSON-line protocol for communication between Elixir and the Baileys bridge.

  All messages include a `v` field indicating the protocol version. Currently
  only version 1 is supported. Unknown versions are rejected so that future
  protocol changes can be detected early.
  """

  @version 1

  @doc "Encode a command request as a JSON string with version envelope."
  @spec encode_request(String.t(), String.t(), map()) :: {:ok, String.t()} | {:error, Jason.EncodeError.t()}
  def encode_request(id, cmd, args) when is_binary(id) and is_binary(cmd) and is_map(args) do
    Jason.encode(%{v: @version, id: id, cmd: cmd, args: args})
  end

  @doc "Decode a JSON line from the bridge. Rejects unsupported versions."
  @spec decode_line(String.t()) :: {:ok, map()} | {:error, :unsupported_version | :invalid_json}
  def decode_line(line) when is_binary(line) do
    case Jason.decode(line) do
      {:ok, %{"v" => v} = msg} when v == @version -> {:ok, msg}
      {:ok, %{"v" => _}} -> {:error, :unsupported_version}
      {:ok, msg} when is_map(msg) -> {:ok, msg}
      {:error, _} -> {:error, :invalid_json}
    end
  end
end
