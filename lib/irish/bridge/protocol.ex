defmodule Irish.Bridge.Protocol do
  @moduledoc """
  Versioned JSON-line protocol for communication between Elixir and the Baileys bridge.

  All messages include a `v` field indicating the protocol version. Currently
  only version 1 is supported. Unknown versions are rejected so that future
  protocol changes can be detected early.
  """

  @version 1

  @doc "Encode a command request as a JSON string with version envelope."
  @spec encode_request(String.t(), String.t(), map()) ::
          {:ok, String.t()} | {:error, Jason.EncodeError.t()}
  def encode_request(id, cmd, args) when is_binary(id) and is_binary(cmd) and is_map(args) do
    Jason.encode(%{v: @version, id: id, cmd: cmd, args: args})
  end

  @doc "Encode a response to a bridge request (bidirectional protocol)."
  @spec encode_response(String.t(), {:ok, term()} | {:error, term()}) ::
          {:ok, String.t()} | {:error, Jason.EncodeError.t()}
  def encode_response(id, {:ok, data}) when is_binary(id) do
    Jason.encode(%{v: @version, id: id, ok: true, data: data})
  end

  def encode_response(id, {:error, reason}) when is_binary(id) do
    Jason.encode(%{v: @version, id: id, ok: false, error: to_string(reason)})
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

  @doc """
  Classify a decoded message by type.

  Returns `:request` for bridge-to-Elixir requests (has `"req"` field),
  `:response` for command responses (has `"ok"` field), or `:event` for events.
  """
  @spec message_type(map()) :: :request | :response | :event
  def message_type(%{"req" => _}), do: :request
  def message_type(%{"ok" => _}), do: :response
  def message_type(%{"event" => _}), do: :event
  def message_type(_), do: :event
end
