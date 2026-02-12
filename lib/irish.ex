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

      # Listen for events (struct-based by default)
      receive do
        {:wa, "connection.update", %{"qr" => qr}} ->
          # Display QR code for scanning
        {:wa, "connection.update", %{"connection" => "open"}} ->
          # Connected!
        {:wa, "messages.upsert", %{messages: messages, type: :notify}} ->
          for msg <- messages do
            IO.puts("\#{msg.push_name}: \#{Irish.Message.text(msg)}")
          end
      end

      # Send a message
      {:ok, msg} = Irish.send_message(pid, "1234567890@s.whatsapp.net", %{text: "Hello!"})

  ## Events

  All Baileys events are forwarded to the handler process as `{:wa, event_name, data}`.
  By default, event data is converted to structs (see `Irish.Event`). Pass
  `struct_events: false` to receive raw maps instead.

  Key events and their struct shapes:

  - `"connection.update"` — raw map (QR codes, connection state)
  - `"messages.upsert"` — `%{messages: [%Irish.Message{}], type: :notify | :append}`
  - `"messages.update"` — `[%{key: %Irish.MessageKey{}, update: map}]`
  - `"chats.upsert"` — `[%Irish.Chat{}]`
  - `"contacts.upsert"` — `[%Irish.Contact{}]`
  - `"groups.update"` — `[%Irish.Group{}]`
  - `"group-participants.update"` — raw map
  - `"presence.update"` — `%{id: jid, presences: %{jid => %Irish.Presence{}}}`
  - `"call"` — `[%Irish.Call{}]`

  ## Options

  - `:auth_dir` — directory to store WhatsApp session (default: `./wa_auth`)
  - `:handler` — PID to receive `{:wa, event, data}` messages (default: caller)
  - `:name` — optional registered name for the process
  - `:config` — Baileys socket config overrides (map)
  - `:timeout` — default command timeout in ms (default: 30_000)
  - `:struct_events` — convert event data to structs (default: `true`)
  """

  alias Irish.{MessageKey, Message}

  @type conn :: GenServer.server()
  @type jid :: String.t()
  @type receipt_type :: String.t()

  @valid_receipt_types ~w(read read-self played)
  @jid_suffixes ~w(@s.whatsapp.net @g.us @broadcast @lid @newsletter)

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: opts[:name] || __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: Irish.Connection.start_link(opts)

  # -- Messaging --

  @doc "Send a message. Content is a map matching Baileys' AnyMessageContent. Returns `{:ok, %Irish.Message{}}` on success."
  @spec send_message(conn(), jid(), map(), map()) :: {:ok, Message.t()} | {:error, any()}
  def send_message(conn, jid, content, opts \\ %{}) do
    with :ok <- validate_jid(jid) do
      case Irish.Connection.command(conn, "send_message", %{
             jid: jid,
             content: content,
             options: opts
           }) do
        {:ok, data} when is_map(data) -> {:ok, Message.from_raw(data)}
        other -> other
      end
    end
  end

  @doc "Mark messages as read. Accepts `%Irish.MessageKey{}` structs or raw maps."
  @spec read_messages(conn(), [MessageKey.t() | map()]) :: {:ok, any()} | {:error, any()}
  def read_messages(conn, keys) do
    Irish.Connection.command(conn, "read_messages", %{keys: normalize_keys(keys)})
  end

  @doc "Send presence update: `available`, `unavailable`, `composing`, `recording`, `paused`."
  @spec send_presence(conn(), String.t(), String.t() | nil) :: {:ok, any()} | {:error, any()}
  def send_presence(conn, type, jid \\ nil) do
    Irish.Connection.command(conn, "send_presence_update", %{type: type, jid: jid})
  end

  @doc "Subscribe to presence updates for a JID."
  @spec presence_subscribe(conn(), jid()) :: {:ok, any()} | {:error, any()}
  def presence_subscribe(conn, jid) do
    with :ok <- validate_jid(jid) do
      Irish.Connection.command(conn, "presence_subscribe", %{jid: jid})
    end
  end

  @doc """
  React to a message with an emoji. Accepts `%Irish.MessageKey{}` or a raw map.

  ## Example

      Irish.react(conn, "123@s.whatsapp.net", message_key, "👍")
  """
  @spec react(conn(), String.t(), MessageKey.t() | map(), String.t()) ::
          {:ok, Message.t()} | {:error, any()}
  def react(conn, jid, message_key, emoji) do
    send_message(conn, jid, %{react: %{text: emoji, key: normalize_key(message_key)}})
  end

  @doc "Remove a reaction from a message. Accepts `%Irish.MessageKey{}` or a raw map."
  @spec unreact(conn(), String.t(), MessageKey.t() | map()) ::
          {:ok, Message.t()} | {:error, any()}
  def unreact(conn, jid, message_key) do
    react(conn, jid, message_key, "")
  end

  @doc """
  Send granular read receipts. Accepts `%Irish.MessageKey{}` structs or raw maps.

  Type can be `"read"`, `"read-self"`, or `"played"`.
  """
  @spec send_receipts(conn(), [MessageKey.t() | map()], receipt_type()) ::
          {:ok, any()} | {:error, any()}
  def send_receipts(conn, keys, type) do
    with :ok <- validate_receipt_type(type) do
      Irish.Connection.command(conn, "send_receipts", %{keys: normalize_keys(keys), type: type})
    end
  end

  # -- Media --

  @doc """
  Download media from a received message.

  Pass the full message map (as received in the `messages.upsert` event).
  Returns `{:ok, binary}` with the decrypted media bytes.
  """
  @spec download_media(conn(), map()) :: {:ok, binary()} | {:error, any()}
  def download_media(conn, message) do
    case Irish.Connection.command(conn, "download_media", %{message: message}) do
      {:ok, %{"__b64" => b64}} -> {:ok, Base.decode64!(b64)}
      {:ok, data} -> {:ok, data}
      error -> error
    end
  end

  # -- Profile --

  @doc "Get profile picture URL."
  @spec profile_picture_url(conn(), String.t(), String.t()) :: {:ok, String.t()} | {:error, any()}
  def profile_picture_url(conn, jid, type \\ "preview") do
    Irish.Connection.command(conn, "profile_picture_url", %{jid: jid, type: type})
  end

  @doc "Update your status/about text."
  @spec update_profile_status(conn(), String.t()) :: {:ok, any()} | {:error, any()}
  def update_profile_status(conn, status) do
    Irish.Connection.command(conn, "update_profile_status", %{status: status})
  end

  @doc "Update your display name."
  @spec update_profile_name(conn(), String.t()) :: {:ok, any()} | {:error, any()}
  def update_profile_name(conn, name) do
    Irish.Connection.command(conn, "update_profile_name", %{name: name})
  end

  @doc "Fetch status/about for JIDs."
  @spec fetch_status(conn(), [String.t()]) :: {:ok, any()} | {:error, any()}
  def fetch_status(conn, jids) when is_list(jids) do
    Irish.Connection.command(conn, "fetch_status", %{jids: jids})
  end

  @doc "Check if phone numbers are on WhatsApp."
  @spec on_whatsapp(conn(), [String.t()]) :: {:ok, any()} | {:error, any()}
  def on_whatsapp(conn, phone_numbers) when is_list(phone_numbers) do
    Irish.Connection.command(conn, "on_whatsapp", %{phone_numbers: phone_numbers})
  end

  @doc "Update profile picture for a JID. Content should be image binary data."
  @spec update_profile_picture(conn(), String.t(), binary()) :: {:ok, any()} | {:error, any()}
  def update_profile_picture(conn, jid, content) when is_binary(content) do
    Irish.Connection.command(conn, "update_profile_picture", %{
      jid: jid,
      content: encode_binary(content)
    })
  end

  @doc "Remove profile picture for a JID."
  @spec remove_profile_picture(conn(), String.t()) :: {:ok, any()} | {:error, any()}
  def remove_profile_picture(conn, jid) do
    Irish.Connection.command(conn, "remove_profile_picture", %{jid: jid})
  end

  # -- Groups --

  @doc "Get group metadata. Returns `{:ok, %Irish.Group{}}` on success."
  @spec group_metadata(conn(), String.t()) :: {:ok, Irish.Group.t()} | {:error, any()}
  def group_metadata(conn, jid) do
    case Irish.Connection.command(conn, "group_metadata", %{jid: jid}) do
      {:ok, data} -> {:ok, Irish.Group.from_raw(data)}
      error -> error
    end
  end

  @doc "Create a group. Returns `{:ok, %Irish.Group{}}` on success."
  @spec group_create(conn(), String.t(), [String.t()]) :: {:ok, Irish.Group.t()} | {:error, any()}
  def group_create(conn, subject, participants) do
    with :ok <- validate_non_empty_list(participants, :empty_participants) do
      case Irish.Connection.command(conn, "group_create", %{
             subject: subject,
             participants: participants
           }) do
        {:ok, data} -> {:ok, Irish.Group.from_raw(data)}
        error -> error
      end
    end
  end

  @doc "Update group name."
  @spec group_update_subject(conn(), String.t(), String.t()) :: {:ok, any()} | {:error, any()}
  def group_update_subject(conn, jid, subject) do
    Irish.Connection.command(conn, "group_update_subject", %{jid: jid, subject: subject})
  end

  @doc "Update group description."
  @spec group_update_description(conn(), String.t(), String.t()) :: {:ok, any()} | {:error, any()}
  def group_update_description(conn, jid, description) do
    Irish.Connection.command(conn, "group_update_description", %{
      jid: jid,
      description: description
    })
  end

  @doc "Add/remove/promote/demote group participants."
  @spec group_participants_update(conn(), jid(), [String.t()], String.t()) ::
          {:ok, any()} | {:error, any()}
  def group_participants_update(conn, jid, participants, action)
      when action in ~w(add remove promote demote) do
    with :ok <- validate_non_empty_list(participants, :empty_participants) do
      Irish.Connection.command(conn, "group_participants_update", %{
        jid: jid,
        participants: participants,
        action: action
      })
    end
  end

  @doc "Get group invite code."
  @spec group_invite_code(conn(), String.t()) :: {:ok, String.t()} | {:error, any()}
  def group_invite_code(conn, jid) do
    Irish.Connection.command(conn, "group_invite_code", %{jid: jid})
  end

  @doc "Leave a group."
  @spec group_leave(conn(), String.t()) :: {:ok, any()} | {:error, any()}
  def group_leave(conn, jid) do
    Irish.Connection.command(conn, "group_leave", %{jid: jid})
  end

  @doc """
  Fetch all groups the account participates in.

  Returns `{:ok, [%Irish.Group{}, ...]}` — a flat list of group structs.
  """
  @spec group_fetch_all(conn()) :: {:ok, [Irish.Group.t()]} | {:error, any()}
  def group_fetch_all(conn) do
    case Irish.Connection.command(conn, "group_fetch_all_participating", %{}) do
      {:ok, groups} when is_map(groups) ->
        {:ok, Enum.map(groups, fn {_jid, data} -> Irish.Group.from_raw(data) end)}

      {:ok, groups} when is_list(groups) ->
        {:ok, Enum.map(groups, &Irish.Group.from_raw/1)}

      error ->
        error
    end
  end

  @doc "Toggle disappearing messages. Expiration is in seconds (0 to disable)."
  @spec group_toggle_ephemeral(conn(), String.t(), integer()) :: {:ok, any()} | {:error, any()}
  def group_toggle_ephemeral(conn, jid, expiration) do
    Irish.Connection.command(conn, "group_toggle_ephemeral", %{jid: jid, expiration: expiration})
  end

  @doc """
  Update group settings.

  Setting must be one of: `"announcement"`, `"not_announcement"`, `"locked"`, `"unlocked"`.
  """
  @spec group_setting_update(conn(), String.t(), String.t()) :: {:ok, any()} | {:error, any()}
  def group_setting_update(conn, jid, setting)
      when setting in ~w(announcement not_announcement locked unlocked) do
    Irish.Connection.command(conn, "group_setting_update", %{jid: jid, setting: setting})
  end

  @doc "Revoke a group's invite link and generate a new one."
  @spec group_revoke_invite(conn(), String.t()) :: {:ok, any()} | {:error, any()}
  def group_revoke_invite(conn, jid) do
    Irish.Connection.command(conn, "group_revoke_invite", %{jid: jid})
  end

  @doc "Accept a group invite by code."
  @spec group_accept_invite(conn(), String.t()) :: {:ok, any()} | {:error, any()}
  def group_accept_invite(conn, code) do
    Irish.Connection.command(conn, "group_accept_invite", %{code: code})
  end

  @doc "Get info about a group invite link without joining. Returns `{:ok, %Irish.Group{}}` on success."
  @spec group_get_invite_info(conn(), String.t()) :: {:ok, Irish.Group.t()} | {:error, any()}
  def group_get_invite_info(conn, code) do
    case Irish.Connection.command(conn, "group_get_invite_info", %{code: code}) do
      {:ok, data} when is_map(data) -> {:ok, Irish.Group.from_raw(data)}
      other -> other
    end
  end

  @doc "List pending join requests for a group."
  @spec group_request_participants_list(conn(), String.t()) :: {:ok, any()} | {:error, any()}
  def group_request_participants_list(conn, jid) do
    Irish.Connection.command(conn, "group_request_participants_list", %{jid: jid})
  end

  @doc "Approve or reject pending join requests. Action: `\"approve\"` or `\"reject\"`."
  @spec group_request_participants_update(conn(), String.t(), [String.t()], String.t()) ::
          {:ok, any()} | {:error, any()}
  def group_request_participants_update(conn, jid, participants, action)
      when action in ~w(approve reject) do
    Irish.Connection.command(conn, "group_request_participants_update", %{
      jid: jid,
      participants: participants,
      action: action
    })
  end

  @doc "Set who can add members. Mode: `\"admin_add\"` or `\"all_member_add\"`."
  @spec group_member_add_mode(conn(), String.t(), String.t()) :: {:ok, any()} | {:error, any()}
  def group_member_add_mode(conn, jid, mode) when mode in ~w(admin_add all_member_add) do
    Irish.Connection.command(conn, "group_member_add_mode", %{jid: jid, mode: mode})
  end

  @doc "Toggle join approval. Mode: `\"on\"` or `\"off\"`."
  @spec group_join_approval_mode(conn(), String.t(), String.t()) :: {:ok, any()} | {:error, any()}
  def group_join_approval_mode(conn, jid, mode) when mode in ~w(on off) do
    Irish.Connection.command(conn, "group_join_approval_mode", %{jid: jid, mode: mode})
  end

  # -- Chat --

  @doc """
  Modify chat properties (archive, pin, mute, etc.).

  ## Examples

      Irish.chat_modify(conn, jid, %{archive: true, lastMessages: [last_msg]})
      Irish.chat_modify(conn, jid, %{pin: true})
      Irish.chat_modify(conn, jid, %{mute: 8 * 60 * 60})  # mute 8 hours
  """
  @spec chat_modify(conn(), String.t(), map()) :: {:ok, any()} | {:error, any()}
  def chat_modify(conn, jid, mod) do
    Irish.Connection.command(conn, "chat_modify", %{jid: jid, mod: mod})
  end

  @doc "Star or unstar messages. Messages is a list of message maps."
  @spec star_messages(conn(), String.t(), [map()], boolean()) :: {:ok, any()} | {:error, any()}
  def star_messages(conn, jid, messages, star) when is_boolean(star) do
    Irish.Connection.command(conn, "star_messages", %{jid: jid, messages: messages, star: star})
  end

  # -- Privacy --

  @doc "Block or unblock a JID."
  @spec update_block_status(conn(), String.t(), String.t()) :: {:ok, any()} | {:error, any()}
  def update_block_status(conn, jid, action) when action in ~w(block unblock) do
    Irish.Connection.command(conn, "update_block_status", %{jid: jid, action: action})
  end

  @doc "Fetch the blocklist."
  @spec fetch_blocklist(conn()) :: {:ok, any()} | {:error, any()}
  def fetch_blocklist(conn) do
    Irish.Connection.command(conn, "fetch_blocklist", %{})
  end

  # -- Auth --

  @doc "Request a pairing code for phone-number-based login (no QR scan needed)."
  @spec request_pairing_code(conn(), String.t(), String.t() | nil) ::
          {:ok, any()} | {:error, any()}
  def request_pairing_code(conn, phone_number, custom_code \\ nil) do
    Irish.Connection.command(conn, "request_pairing_code", %{
      phone_number: phone_number,
      custom_code: custom_code
    })
  end

  @doc "Log out and invalidate the session."
  @spec logout(conn()) :: {:ok, any()} | {:error, any()}
  def logout(conn) do
    Irish.Connection.command(conn, "logout", %{})
  end

  # -- Helpers --

  defp normalize_key(%MessageKey{} = key), do: MessageKey.to_raw(key)
  defp normalize_key(raw) when is_map(raw), do: raw

  defp normalize_keys(keys) when is_list(keys), do: Enum.map(keys, &normalize_key/1)

  defp encode_binary(data) when is_binary(data), do: %{"__b64" => Base.encode64(data)}

  # -- Validators --

  defp validate_jid(jid) when is_binary(jid) do
    if Enum.any?(@jid_suffixes, &String.ends_with?(jid, &1)),
      do: :ok,
      else: {:error, :invalid_jid}
  end

  defp validate_jid(_), do: {:error, :invalid_jid}

  defp validate_receipt_type(type) when type in @valid_receipt_types, do: :ok
  defp validate_receipt_type(_), do: {:error, :invalid_receipt_type}

  defp validate_non_empty_list([_ | _], _error), do: :ok
  defp validate_non_empty_list(_, error), do: {:error, error}
end
