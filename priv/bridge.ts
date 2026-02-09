#!/usr/bin/env -S deno run --allow-all --node-modules-dir=auto
/**
 * Irish Bridge — Connects Elixir to Baileys via JSON lines over stdio.
 *
 * Protocol:
 *   Elixir -> Bridge (commands):  {"id":"…","cmd":"…","args":{…}}
 *   Bridge -> Elixir (responses): {"id":"…","ok":true,"data":{…}}
 *   Bridge -> Elixir (events):    {"event":"…","data":{…}}
 */

import makeWASocket, {
  useMultiFileAuthState,
  DisconnectReason,
  makeCacheableSignalKeyStore,
  type WASocket,
  type BaileysEventMap,
} from "baileys";

// ---------------------------------------------------------------------------
// Logger — must write to stderr so stdout stays clean for the JSON protocol
// ---------------------------------------------------------------------------

type LogFn = (...args: unknown[]) => void;

interface Logger {
  level: string;
  trace: LogFn;
  debug: LogFn;
  info: LogFn;
  warn: LogFn;
  error: LogFn;
  fatal: LogFn;
  child: (bindings: Record<string, unknown>) => Logger;
}

function makeLogger(level = "warn"): Logger {
  const levels = ["trace", "debug", "info", "warn", "error", "fatal"];
  const threshold = levels.indexOf(level);
  const enc = new TextEncoder();

  const write = (lvl: string, args: unknown[]) => {
    if (levels.indexOf(lvl) < threshold) return;
    const parts = args.map((a) =>
      typeof a === "string" ? a : JSON.stringify(a)
    );
    Deno.stderr.writeSync(
      enc.encode(`[${lvl.toUpperCase()}] ${parts.join(" ")}\n`)
    );
  };

  const logger: Logger = {
    level,
    trace: (...a) => write("trace", a),
    debug: (...a) => write("debug", a),
    info: (...a) => write("info", a),
    warn: (...a) => write("warn", a),
    error: (...a) => write("error", a),
    fatal: (...a) => write("fatal", a),
    child: () => makeLogger(level),
  };
  return logger;
}

const logger = makeLogger("warn");

// ---------------------------------------------------------------------------
// JSON serialization — handles Buffer / Uint8Array / BigInt
// ---------------------------------------------------------------------------

function uint8ToBase64(bytes: Uint8Array): string {
  const chunks: string[] = [];
  const sz = 0x8000;
  for (let i = 0; i < bytes.length; i += sz) {
    chunks.push(String.fromCharCode(...bytes.subarray(i, i + sz)));
  }
  return btoa(chunks.join(""));
}

function replacer(_key: string, value: unknown): unknown {
  if (value instanceof Uint8Array) {
    return { __b64: uint8ToBase64(value) };
  }
  if (typeof value === "bigint") {
    return Number(value);
  }
  if (typeof value === "object" && value !== null) {
    const v = value as Record<string, unknown>;
    if (v.type === "Buffer" && Array.isArray(v.data)) {
      return { __b64: uint8ToBase64(new Uint8Array(v.data as number[])) };
    }
  }
  return value;
}

// ---------------------------------------------------------------------------
// Stdio protocol
// ---------------------------------------------------------------------------

const enc = new TextEncoder();

function emit(msg: Record<string, unknown>) {
  Deno.stdout.writeSync(enc.encode(JSON.stringify(msg, replacer) + "\n"));
}

async function* readLines(): AsyncGenerator<string> {
  const reader = Deno.stdin.readable.getReader();
  const decoder = new TextDecoder();
  let buf = "";
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    buf += decoder.decode(value, { stream: true });
    const lines = buf.split("\n");
    buf = lines.pop()!;
    for (const line of lines) {
      if (line.trim()) yield line;
    }
  }
}

// ---------------------------------------------------------------------------
// Baileys connection
// ---------------------------------------------------------------------------

const EVENTS: (keyof BaileysEventMap)[] = [
  "connection.update",
  "creds.update",
  "messaging-history.set",
  "chats.upsert",
  "chats.update",
  "chats.delete",
  "contacts.upsert",
  "contacts.update",
  "messages.upsert",
  "messages.update",
  "messages.delete",
  "messages.reaction",
  "messages.media-update",
  "message-receipt.update",
  "groups.upsert",
  "groups.update",
  "group-participants.update",
  "group.join-request",
  "presence.update",
  "blocklist.set",
  "blocklist.update",
  "call",
  "labels.edit",
  "labels.association",
];

let sock: WASocket | null = null;
const msgCache = new Map<string, unknown>();
const MAX_CACHE = 5000;

async function connect(
  authDir: string,
  config: Record<string, unknown> = {}
) {
  const { state, saveCreds } = await useMultiFileAuthState(authDir);

  sock = makeWASocket({
    auth: {
      creds: state.creds,
      keys: makeCacheableSignalKeyStore(state.keys, logger as any),
    },
    logger: logger as any,
    browser: ["Irish", "Elixir", "1.0.0"] as [string, string, string],
    printQRInTerminal: false,
    getMessage: async (key) => msgCache.get(key.id ?? "") as any,
    ...config,
  } as any);

  // Forward every event to Elixir
  for (const event of EVENTS) {
    sock.ev.on(event, (data: unknown) => {
      // Cache messages for retry decryption
      if (event === "messages.upsert") {
        const msgs = (data as any).messages as any[];
        for (const m of msgs) {
          if (m.message && m.key?.id) {
            if (msgCache.size >= MAX_CACHE) {
              const oldest = msgCache.keys().next().value;
              if (oldest) msgCache.delete(oldest);
            }
            msgCache.set(m.key.id, m.message);
          }
        }
      }
      emit({ event, data });
    });
  }

  // Persist credentials on update
  sock.ev.on("creds.update", saveCreds);

  // Handle disconnects
  sock.ev.on("connection.update", ({ connection, lastDisconnect }) => {
    if (connection === "close") {
      const code = (lastDisconnect?.error as any)?.output?.statusCode;
      if (code === DisconnectReason.loggedOut) {
        emit({ event: "__exit", data: { reason: "logged_out" } });
        Deno.exit(1);
      }
      logger.info("Reconnecting…");
      connect(authDir, config);
    }
  });
}

// ---------------------------------------------------------------------------
// Command dispatch
// ---------------------------------------------------------------------------

type Cmd = { id?: string; cmd: string; args: Record<string, any> };

async function handle(c: Cmd): Promise<unknown> {
  if (!sock) throw new Error("not_connected");
  const a = c.args;

  switch (c.cmd) {
    // --- messaging ---
    case "send_message":
      return sock.sendMessage(a.jid, a.content, a.options);
    case "read_messages":
      await sock.readMessages(a.keys);
      return null;
    case "send_presence_update":
      await sock.sendPresenceUpdate(a.type, a.jid);
      return null;
    case "presence_subscribe":
      await sock.presenceSubscribe(a.jid);
      return null;

    // --- profile ---
    case "profile_picture_url":
      return sock.profilePictureUrl(a.jid, a.type || "preview");
    case "update_profile_status":
      await sock.updateProfileStatus(a.status);
      return null;
    case "update_profile_name":
      await sock.updateProfileName(a.name);
      return null;
    case "fetch_status":
      return sock.fetchStatus(...a.jids);
    case "on_whatsapp":
      return sock.onWhatsApp(...a.phone_numbers);

    // --- groups ---
    case "group_metadata":
      return sock.groupMetadata(a.jid);
    case "group_create":
      return sock.groupCreate(a.subject, a.participants);
    case "group_update_subject":
      await sock.groupUpdateSubject(a.jid, a.subject);
      return null;
    case "group_update_description":
      await sock.groupUpdateDescription(a.jid, a.description);
      return null;
    case "group_participants_update":
      return sock.groupParticipantsUpdate(a.jid, a.participants, a.action);
    case "group_invite_code":
      return sock.groupInviteCode(a.jid);
    case "group_leave":
      await sock.groupLeave(a.jid);
      return null;
    case "group_fetch_all_participating":
      return sock.groupFetchAllParticipating();

    // --- privacy ---
    case "update_block_status":
      await sock.updateBlockStatus(a.jid, a.action);
      return null;
    case "fetch_blocklist":
      return sock.fetchBlocklist();

    // --- auth ---
    case "request_pairing_code":
      return sock.requestPairingCode(a.phone_number, a.custom_code);
    case "logout":
      await sock.logout(a.msg);
      return null;

    default:
      throw new Error(`unknown_command: ${c.cmd}`);
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  const stdin = readLines();

  // First message must be the init command
  const first = await stdin.next();
  if (first.done) Deno.exit(1);

  const init: Cmd = JSON.parse(first.value);
  if (init.cmd !== "init") {
    logger.error("First command must be init");
    Deno.exit(1);
  }

  try {
    await connect(init.args.auth_dir || "./auth", init.args.config || {});
    emit({ id: init.id, ok: true, data: { status: "initialized" } });
  } catch (err) {
    emit({
      id: init.id,
      ok: false,
      error: err instanceof Error ? err.message : String(err),
    });
    Deno.exit(1);
  }

  // Command loop
  for await (const line of stdin) {
    let id: string | undefined;
    try {
      const cmd: Cmd = JSON.parse(line);
      id = cmd.id;
      const result = await handle(cmd);
      emit({ id, ok: true, data: result ?? null });
    } catch (err) {
      emit({
        id,
        ok: false,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }
}

main();
