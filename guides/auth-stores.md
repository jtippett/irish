# Custom Auth Stores

By default, Irish stores WhatsApp credentials and Signal keys as JSON files in
`auth_dir`. For production deployments — containers, multi-instance setups,
managed platforms — you'll want to store auth state in a database, Redis, or
other persistent backend.

## How it works

Irish delegates all auth persistence to a module implementing the
`Irish.Auth.Store` behaviour. During connection setup, the Baileys bridge
calls back to Elixir for credential and key operations:

```
Bridge                          Elixir Connection
  |                                  |
  |--{req: "auth.load_creds"}------>|
  |                                  | Store.load_creds(opts)
  |<---{ok: true, data: creds}------|
  |                                  |
  | (Baileys encrypts a message)     |
  |--{req: "auth.keys_get"}-------->|
  |                                  | Store.get(type, ids, opts)
  |<---{ok: true, data: keys}-------|
```

Values are **opaque** — your store persists and returns them verbatim. You
never need to interpret Signal protocol data.

## Using `auth_store`

Pass `auth_store: {module, opts}` when starting Irish:

```elixir
# File-based (equivalent to auth_dir: "/tmp/wa_auth")
Irish.start_link(auth_store: {Irish.Auth.Store.File, dir: "/tmp/wa_auth"})

# Custom store
Irish.start_link(auth_store: {MyApp.WAStore, repo: MyApp.Repo, user_id: 42})
```

The `auth_dir` option is shorthand — `auth_dir: "/tmp/wa_auth"` maps to
`auth_store: {Irish.Auth.Store.File, dir: "/tmp/wa_auth"}`.

## Implementing a store

Implement the four callbacks in `Irish.Auth.Store`:

```elixir
defmodule MyApp.WAStore do
  @behaviour Irish.Auth.Store

  @impl true
  def load_creds(opts) do
    repo = Keyword.fetch!(opts, :repo)
    user_id = Keyword.fetch!(opts, :user_id)

    case repo.get_by(MyApp.WACreds, user_id: user_id) do
      nil -> :none
      record -> {:ok, Jason.decode!(record.data)}
    end
  end

  @impl true
  def save_creds(creds, opts) do
    repo = Keyword.fetch!(opts, :repo)
    user_id = Keyword.fetch!(opts, :user_id)

    %MyApp.WACreds{user_id: user_id}
    |> Ecto.Changeset.change(data: Jason.encode!(creds))
    |> repo.insert!(on_conflict: :replace_all, conflict_target: :user_id)

    :ok
  end

  @impl true
  def get(type, ids, opts) do
    repo = Keyword.fetch!(opts, :repo)
    user_id = Keyword.fetch!(opts, :user_id)

    keys =
      MyApp.WAKey
      |> MyApp.WAKey.for_user(user_id)
      |> MyApp.WAKey.by_type_and_ids(type, ids)
      |> repo.all()
      |> Map.new(fn k -> {k.key_id, Jason.decode!(k.data)} end)

    {:ok, keys}
  end

  @impl true
  def set(data, opts) do
    repo = Keyword.fetch!(opts, :repo)
    user_id = Keyword.fetch!(opts, :user_id)

    repo.transaction(fn ->
      for {type, entries} <- data, {id, value} <- entries do
        if is_nil(value) do
          MyApp.WAKey
          |> MyApp.WAKey.for_user(user_id)
          |> MyApp.WAKey.by_type_and_ids(type, [id])
          |> repo.delete_all()
        else
          %MyApp.WAKey{user_id: user_id, type: type, key_id: id}
          |> Ecto.Changeset.change(data: Jason.encode!(value))
          |> repo.insert!(on_conflict: :replace_all, conflict_target: [:user_id, :type, :key_id])
        end
      end
    end)

    :ok
  end
end
```

### Schema example

```elixir
defmodule MyApp.WACreds do
  use Ecto.Schema

  schema "wa_creds" do
    field :user_id, :integer
    field :data, :string  # JSON blob
    timestamps()
  end
end

defmodule MyApp.WAKey do
  use Ecto.Schema
  import Ecto.Query

  schema "wa_keys" do
    field :user_id, :integer
    field :type, :string      # "pre-key", "session", "sender-key", etc.
    field :key_id, :string
    field :data, :string      # JSON blob
    timestamps()
  end

  def for_user(query, user_id), do: where(query, [k], k.user_id == ^user_id)

  def by_type_and_ids(query, type, ids) do
    where(query, [k], k.type == ^type and k.key_id in ^ids)
  end
end
```

## Callbacks

| Callback | Called when | Return |
|---|---|---|
| `load_creds(opts)` | Connection starts | `{:ok, map}` or `:none` |
| `save_creds(creds, opts)` | After initial generation and on every credential update | `:ok` |
| `get(type, ids, opts)` | Baileys needs Signal keys (cache miss) | `{:ok, %{id => value}}` |
| `set(data, opts)` | Baileys writes or deletes Signal keys | `:ok` |

**Key types** you'll see in `get`/`set`: `"pre-key"`, `"session"`,
`"sender-key"`, `"sender-key-memory"`, `"app-state-sync-key"`,
`"app-state-sync-version"`.

## Performance

Baileys wraps the key store in a 5-minute in-memory cache
(`CacheableSignalKeyStore`). Most key lookups are cache hits — only cold
starts and cache evictions trigger callbacks to Elixir. Typical per-message
overhead is 0-2 round-trips (~0.5ms each), negligible compared to WhatsApp
network latency.

## Telemetry

Auth store operations emit telemetry events:

- `[:irish, :auth_store, :start]` — `%{req: request_name}`
- `[:irish, :auth_store, :stop]` — `%{req: request_name, result: :ok | :error}`, measurements: `%{duration: native_time}`

Use these to monitor store latency and errors in production.
