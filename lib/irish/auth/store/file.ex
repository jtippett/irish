defmodule Irish.Auth.Store.File do
  @moduledoc """
  File-based auth store matching Baileys' `useMultiFileAuthState` layout.

  Credentials are stored in `creds.json`. Signal keys are stored as individual
  JSON files named `{type}-{id}.json` (slashes replaced with `__`, colons
  with `-`).

  This is the default store used when you pass `auth_dir: "/path"` to
  `Irish.start_link/1`.
  """

  @behaviour Irish.Auth.Store

  @impl true
  def load_creds(opts) do
    path = creds_path(opts)

    case File.read(path) do
      {:ok, data} -> {:ok, Jason.decode!(data)}
      {:error, :enoent} -> :none
      {:error, reason} -> raise "failed to read #{path}: #{inspect(reason)}"
    end
  end

  @impl true
  def save_creds(creds, opts) do
    path = creds_path(opts)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(creds))
    :ok
  end

  @impl true
  def get(type, ids, opts) do
    dir = Keyword.fetch!(opts, :dir)

    result =
      Map.new(ids, fn id ->
        path = key_path(dir, type, id)

        value =
          case File.read(path) do
            {:ok, data} -> Jason.decode!(data)
            {:error, :enoent} -> nil
            {:error, reason} -> raise "failed to read #{path}: #{inspect(reason)}"
          end

        {id, value}
      end)
      |> Enum.reject(fn {_id, v} -> is_nil(v) end)
      |> Map.new()

    {:ok, result}
  end

  @impl true
  def set(data, opts) do
    dir = Keyword.fetch!(opts, :dir)

    for {type, entries} <- data, {id, value} <- entries do
      path = key_path(dir, type, id)

      if is_nil(value) do
        File.rm(path)
      else
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, Jason.encode!(value))
      end
    end

    :ok
  end

  defp creds_path(opts) do
    dir = Keyword.fetch!(opts, :dir)
    Path.join(dir, "creds.json")
  end

  defp key_path(dir, type, id) do
    filename = sanitize(type) <> "-" <> sanitize(id) <> ".json"
    Path.join(dir, filename)
  end

  defp sanitize(name) do
    name
    |> String.replace("/", "__")
    |> String.replace(":", "-")
  end
end
