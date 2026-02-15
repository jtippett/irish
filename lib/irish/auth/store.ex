defmodule Irish.Auth.Store do
  @moduledoc """
  Behaviour for pluggable WhatsApp auth state persistence.

  Irish delegates credential and Signal key storage to the module you provide
  via the `:auth_store` option. Implement this behaviour to store auth state
  in a database, Redis, S3, or any other backend.

  ## Usage

      # Use the built-in file store (equivalent to just passing :auth_dir)
      Irish.start_link(auth_store: {Irish.Auth.Store.File, dir: "/tmp/wa_auth"})

      # Use a custom store
      Irish.start_link(auth_store: {MyApp.WAStore, repo: MyApp.Repo})

  ## Values are opaque

  Credential and key values are JSON-serializable maps produced by Baileys.
  Your store should persist and return them verbatim — never interpret or
  modify the contents.
  """

  @type opts :: keyword()

  @doc """
  Load saved credentials.

  Return `{:ok, creds_map}` if credentials exist, or `:none` for a fresh
  session (the bridge will generate initial credentials and call `save_creds/2`).
  """
  @callback load_creds(opts()) :: {:ok, map()} | :none

  @doc """
  Persist credentials. Called after initial generation and on every `creds.update` event.
  """
  @callback save_creds(creds :: map(), opts()) :: :ok

  @doc """
  Fetch Signal keys by type and IDs.

  `type` is a string like `"pre-key"`, `"session"`, `"sender-key"`, etc.
  Return a map of `%{id => value}` for the IDs that exist. Missing IDs
  should be omitted from the result (not set to nil).
  """
  @callback get(type :: String.t(), ids :: [String.t()], opts()) :: {:ok, %{String.t() => map()}}

  @doc """
  Persist or delete Signal keys.

  `data` is a map of `%{type => %{id => value | nil}}`. A `nil` value means
  the key should be deleted.
  """
  @callback set(data :: %{String.t() => %{String.t() => map() | nil}}, opts()) :: :ok
end
