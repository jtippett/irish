defmodule Irish.Test.MemoryStore do
  @moduledoc false
  @behaviour Irish.Auth.Store

  @doc "Start an Agent to back this store. Returns the agent pid."
  def start do
    {:ok, pid} = Agent.start_link(fn -> %{creds: nil, keys: %{}} end)
    pid
  end

  @impl true
  def load_creds(opts) do
    agent = Keyword.fetch!(opts, :agent)

    case Agent.get(agent, & &1.creds) do
      nil -> :none
      creds -> {:ok, creds}
    end
  end

  @impl true
  def save_creds(creds, opts) do
    agent = Keyword.fetch!(opts, :agent)
    Agent.update(agent, &%{&1 | creds: creds})
    :ok
  end

  @impl true
  def get(type, ids, opts) do
    agent = Keyword.fetch!(opts, :agent)

    keys = Agent.get(agent, & &1.keys)

    result =
      Enum.reduce(ids, %{}, fn id, acc ->
        case get_in(keys, [type, id]) do
          nil -> acc
          value -> Map.put(acc, id, value)
        end
      end)

    {:ok, result}
  end

  @impl true
  def set(data, opts) do
    agent = Keyword.fetch!(opts, :agent)

    Agent.update(agent, fn state ->
      new_keys =
        Enum.reduce(data, state.keys, fn {type, entries}, keys_acc ->
          type_map = Map.get(keys_acc, type, %{})

          updated =
            Enum.reduce(entries, type_map, fn {id, value}, type_acc ->
              if is_nil(value) do
                Map.delete(type_acc, id)
              else
                Map.put(type_acc, id, value)
              end
            end)

          Map.put(keys_acc, type, updated)
        end)

      %{state | keys: new_keys}
    end)

    :ok
  end
end
