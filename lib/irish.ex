defmodule Irish do
  @moduledoc """
  Elixir client for WhatsApp Web via Baileys.

  ## Quick start

      # Add to your supervision tree
      children = [
        {Irish, auth_dir: "/tmp/wa_auth", handler: self(), name: :whatsapp}
      ]

      # Or start directly
      {:ok, pid} = Irish.start_link(auth_dir: "/tmp/wa_auth", handler: self())

      # Listen for events
      receive do
        {:wa, "connection.update", %{"qr" => qr}} ->
          # Display QR code for scanning
        {:wa, "connection.update", %{"connection" => "open"}} ->
          # Connected!
        {:wa, "messages.upsert", %{"messages" => messages}} ->
          # Incoming messages
      end

      # Send a message
      {:ok, _msg} = Irish.send_message(pid, "1234567890@s.whatsapp.net", %{text: "Hello!"})

  ## Events

  All Baileys events are forwarded to the handler process as `{:wa, event_name, data}`.

  Key events:

  - `"connection.update"` — connection state changes, QR codes
  - `"messages.upsert"` — new incoming/outgoing messages
  - `"messages.update"` — message status updates (delivered, read)
  - `"chats.upsert"` — new chats
  - `"contacts.upsert"` — new contacts
  - `"groups.update"` — group metadata changes
  - `"group-participants.update"` — members added/removed
  - `"presence.update"` — online/typing status
  - `"call"` — incoming calls

  ## Options

  - `:auth_dir` — directory to store WhatsApp session (default: `./wa_auth`)
  - `:handler` — PID to receive `{:wa, event, data}` messages (default: caller)
  - `:name` — optional registered name for the process
  - `:config` — Baileys socket config overrides (map)
  - `:timeout` — default command timeout in ms (default: 30_000)
  """

  def child_spec(opts) do
    %{
      id: opts[:name] || __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  def start_link(opts), do: Irish.Connection.start_link(opts)

  # -- Messaging --

  @doc "Send a message. Content is a map matching Baileys' AnyMessageContent."
  def send_message(conn, jid, content, opts \\ %{}) do
    Irish.Connection.command(conn, "send_message", %{jid: jid, content: content, options: opts})
  end

  @doc "Mark messages as read. Keys is a list of `%{remoteJid, fromMe, id}` maps."
  def read_messages(conn, keys) do
    Irish.Connection.command(conn, "read_messages", %{keys: keys})
  end

  @doc "Send presence update: `available`, `unavailable`, `composing`, `recording`, `paused`."
  def send_presence(conn, type, jid \\ nil) do
    Irish.Connection.command(conn, "send_presence_update", %{type: type, jid: jid})
  end

  @doc "Subscribe to presence updates for a JID."
  def presence_subscribe(conn, jid) do
    Irish.Connection.command(conn, "presence_subscribe", %{jid: jid})
  end

  # -- Profile --

  @doc "Get profile picture URL."
  def profile_picture_url(conn, jid, type \\ "preview") do
    Irish.Connection.command(conn, "profile_picture_url", %{jid: jid, type: type})
  end

  @doc "Update your status/about text."
  def update_profile_status(conn, status) do
    Irish.Connection.command(conn, "update_profile_status", %{status: status})
  end

  @doc "Update your display name."
  def update_profile_name(conn, name) do
    Irish.Connection.command(conn, "update_profile_name", %{name: name})
  end

  @doc "Fetch status/about for JIDs."
  def fetch_status(conn, jids) when is_list(jids) do
    Irish.Connection.command(conn, "fetch_status", %{jids: jids})
  end

  @doc "Check if phone numbers are on WhatsApp."
  def on_whatsapp(conn, phone_numbers) when is_list(phone_numbers) do
    Irish.Connection.command(conn, "on_whatsapp", %{phone_numbers: phone_numbers})
  end

  # -- Groups --

  @doc "Get group metadata."
  def group_metadata(conn, jid) do
    Irish.Connection.command(conn, "group_metadata", %{jid: jid})
  end

  @doc "Create a group."
  def group_create(conn, subject, participants) do
    Irish.Connection.command(conn, "group_create", %{subject: subject, participants: participants})
  end

  @doc "Update group name."
  def group_update_subject(conn, jid, subject) do
    Irish.Connection.command(conn, "group_update_subject", %{jid: jid, subject: subject})
  end

  @doc "Update group description."
  def group_update_description(conn, jid, description) do
    Irish.Connection.command(conn, "group_update_description", %{jid: jid, description: description})
  end

  @doc "Add/remove/promote/demote group participants."
  def group_participants_update(conn, jid, participants, action)
      when action in ~w(add remove promote demote) do
    Irish.Connection.command(conn, "group_participants_update", %{
      jid: jid,
      participants: participants,
      action: action
    })
  end

  @doc "Get group invite code."
  def group_invite_code(conn, jid) do
    Irish.Connection.command(conn, "group_invite_code", %{jid: jid})
  end

  @doc "Leave a group."
  def group_leave(conn, jid) do
    Irish.Connection.command(conn, "group_leave", %{jid: jid})
  end

  @doc "Fetch all groups the account participates in."
  def group_fetch_all(conn) do
    Irish.Connection.command(conn, "group_fetch_all_participating", %{})
  end

  # -- Privacy --

  @doc "Block or unblock a JID."
  def update_block_status(conn, jid, action) when action in ~w(block unblock) do
    Irish.Connection.command(conn, "update_block_status", %{jid: jid, action: action})
  end

  @doc "Fetch the blocklist."
  def fetch_blocklist(conn) do
    Irish.Connection.command(conn, "fetch_blocklist", %{})
  end

  # -- Auth --

  @doc "Request a pairing code for phone-number-based login (no QR scan needed)."
  def request_pairing_code(conn, phone_number, custom_code \\ nil) do
    Irish.Connection.command(conn, "request_pairing_code", %{
      phone_number: phone_number,
      custom_code: custom_code
    })
  end

  @doc "Log out and invalidate the session."
  def logout(conn) do
    Irish.Connection.command(conn, "logout", %{})
  end
end
