# Irish Gold Standard Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Elevate Irish to a publish-ready Elixir library with a stable, idiomatic API and a robust, versioned Baileys bridge contract.

**Architecture:** Split responsibilities into transport (`Irish.Transport.Port`), protocol (`Irish.Bridge.Protocol`), and domain (`Irish.*` structs + services). Preserve a thin public facade (`Irish`) while hardening conversion boundaries and making event/command contracts explicit and testable. Add CI/release quality gates so compatibility regressions are caught before publish.

**Tech Stack:** Elixir (GenServer, Telemetry, ExDoc, Dialyzer, Credo), Deno + Baileys bridge, ExUnit.

## Current Review Findings (Why this plan exists)

1. Runtime command timeout behavior is inconsistent (`Irish.command/4` timeout argument only controls `GenServer.call`, while bridge timeout uses a fixed state timeout).
2. Init command acknowledgement is not correlated in `pending`, so initialization success/failure is not modeled as a first-class state transition.
3. Bridge process lifecycle/error semantics are weak (`sock.logout(a.msg)` call shape, reconnect recursion policy, coarse `--allow-all` permissions).
4. Event/data contracts are under-specified for forward compatibility (partial event conversion, no versioned protocol schema, many `any()` specs).
5. Library publishability is incomplete (`mix.exs` lacks Hex package metadata/docs/developer quality gates).
6. Tests are mostly struct parsers; there are no bridge protocol contract tests, connection lifecycle tests, or regression snapshots against Baileys event shapes.

---

### Task 1: Publish-Ready Project Metadata & Quality Gates

**Files:**
- Modify: `mix.exs`
- Create: `.credo.exs`
- Create: `.dialyzer_ignore.exs` (optional if needed)
- Create: `.github/workflows/ci.yml`
- Create: `.github/workflows/release.yml` (or defer until first release)
- Test: `README.md` (installation/publish section)

**Step 1: Write failing tests/checks for project quality baseline**

```bash
mix format --check-formatted
mix test
mix docs
mix credo --strict
mix dialyzer
```

Expected: `mix docs`, `credo`, and `dialyzer` fail because dependencies/config are missing.

**Step 2: Add minimal implementation in `mix.exs`**

```elixir
def project do
  [
    app: :irish,
    version: "0.1.0",
    elixir: "~> 1.16",
    start_permanent: Mix.env() == :prod,
    deps: deps(),
    description: "WhatsApp Web client for Elixir powered by Baileys",
    package: package(),
    docs: docs(),
    source_url: "https://github.com/<org>/irish",
    homepage_url: "https://github.com/<org>/irish"
  ]
end

defp package do
  [
    licenses: ["MIT"],
    links: %{
      "GitHub" => "https://github.com/<org>/irish",
      "Baileys" => "https://github.com/WhiskeySockets/Baileys"
    },
    files: ~w(lib priv mix.exs README.md LICENSE .formatter.exs)
  ]
end

defp docs do
  [
    main: "readme",
    extras: ["README.md"]
  ]
end
```

**Step 3: Add tooling dependencies**

```elixir
{:ex_doc, "~> 0.37", only: :dev, runtime: false},
{:credo, "~> 1.7", only: [:dev, :test], runtime: false},
{:dialyxir, "~> 1.4", only: [:dev], runtime: false}
```

**Step 4: Run checks to confirm pass**

Run: `mix deps.get && mix format && mix test && mix docs`
Expected: all pass.

**Step 5: Commit**

```bash
git add mix.exs .credo.exs .github/workflows/ci.yml README.md
git commit -m "build: add publish metadata and quality gates"
```

---

### Task 2: Version and Formalize Bridge Protocol

**Files:**
- Create: `lib/irish/bridge/protocol.ex`
- Modify: `lib/irish/connection.ex`
- Modify: `priv/bridge.ts`
- Test: `test/irish/bridge/protocol_test.exs`

**Step 1: Write failing protocol tests**

```elixir
defmodule Irish.Bridge.ProtocolTest do
  use ExUnit.Case, async: true

  alias Irish.Bridge.Protocol

  test "encodes request envelope with version" do
    assert {:ok, json} = Protocol.encode_request("abc", "send_message", %{jid: "x"})
    assert json =~ "\"v\":1"
    assert json =~ "\"cmd\":\"send_message\""
  end

  test "rejects unsupported envelope versions" do
    assert {:error, :unsupported_version} =
             Protocol.decode_line(~s({"v":99,"event":"connection.update","data":{}}))
  end
end
```

**Step 2: Add minimal protocol module**

```elixir
defmodule Irish.Bridge.Protocol do
  @version 1

  def encode_request(id, cmd, args) when is_binary(id) and is_binary(cmd) and is_map(args) do
    Jason.encode(%{v: @version, id: id, cmd: cmd, args: args})
  end

  def decode_line(line) when is_binary(line) do
    with {:ok, msg} <- Jason.decode(line),
         1 <- Map.get(msg, "v", 1) do
      {:ok, msg}
    else
      1 -> {:error, :invalid}
      _ -> {:error, :unsupported_version}
    end
  end
end
```

**Step 3: Route `Irish.Connection` encode/decode through protocol module**

Example change:

```elixir
with {:ok, payload} <- Protocol.encode_request(id, cmd, args) do
  Port.command(state.port, payload <> "\n")
end
```

**Step 4: Add bridge-side version field**

`priv/bridge.ts` emit/request parsing should include `v: 1` on all payloads.

**Step 5: Verify**

Run: `mix test test/irish/bridge/protocol_test.exs`
Expected: PASS.

---

### Task 3: Fix Command Timeout Semantics and Init Handshake

**Files:**
- Modify: `lib/irish/connection.ex`
- Create: `test/irish/connection_timeout_test.exs`
- Create: `test/irish/connection_init_test.exs`

**Step 1: Add failing tests for timeout behavior**

```elixir
test "command/4 per-call timeout is honored" do
  # fake state where timeout is 30_000 but call timeout arg is 50
  # assert response timeout happens near requested value
end
```

**Step 2: Implement per-request timeout in envelope**

`Irish.command/4` should pass timeout in call payload:

```elixir
def command(conn, cmd, args \\ %{}, timeout \\ @default_timeout) do
  GenServer.call(conn, {:command, cmd, args, timeout}, timeout + 1000)
end
```

And in `handle_call`:

```elixir
def handle_call({:command, cmd, args, timeout}, from, state) do
  ...
  timer = Process.send_after(self(), {:cmd_timeout, id}, timeout)
end
```

**Step 3: Add explicit init state machine**

- Add `init_ref` pending entry.
- Wait for init ACK before accepting normal commands.
- Return `{:stop, {:init_failed, reason}, state}` if init fails.

**Step 4: Verify**

Run: `mix test test/irish/connection_timeout_test.exs test/irish/connection_init_test.exs`
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/irish/connection.ex test/irish/connection_timeout_test.exs test/irish/connection_init_test.exs
git commit -m "fix: honor per-call timeout and formalize init handshake"
```

---

### Task 4: Harden Bridge Lifecycle and Command Surface

**Files:**
- Modify: `priv/bridge.ts`
- Create: `priv/bridge/commands.ts` (optional refactor)
- Test: `test/irish/bridge/command_contract_test.exs`

**Step 1: Write failing contract tests**

Cases:
- unknown command returns stable error code (`unknown_command`)
- `logout` command dispatches `sock.logout()` with no invalid argument
- command error envelope includes `code`, `message`, `details`

**Step 2: Refactor command dispatch to table-driven map**

```ts
const commands: Record<string, (a: any) => Promise<unknown>> = {
  send_message: (a) => sock!.sendMessage(a.jid, a.content, a.options),
  logout: async () => {
    await sock!.logout();
    return null;
  }
}
```

**Step 3: Narrow Deno permissions in spawn args**

In `lib/irish/connection.ex`, replace broad flags with explicit requirements:

```elixir
{:args, ["run", "--allow-net", "--allow-read", "--allow-write", "--allow-env", "--node-modules-dir=manual", bridge_path]}
```

(Verify the exact minimum permission set by running integration tests.)

**Step 4: Add reconnect guard**

Prevent overlapping reconnect attempts with a boolean latch.

**Step 5: Verify**

Run: `mix test test/irish/bridge/command_contract_test.exs`
Expected: PASS with deterministic envelopes.

---

### Task 5: Make Event Types Explicit and Extensible

**Files:**
- Create: `lib/irish/event/types.ex`
- Modify: `lib/irish/event.ex`
- Modify: `lib/irish.ex`
- Test: `test/irish/event_types_test.exs`

**Step 1: Write failing tests for typed event envelopes**

```elixir
test "messages.upsert returns typed struct envelope" do
  raw = %{"type" => "notify", "messages" => []}
  assert %Irish.Event.MessagesUpsert{type: :notify, messages: []} =
           Irish.Event.convert("messages.upsert", raw)
end
```

**Step 2: Add event structs**

```elixir
defmodule Irish.Event.MessagesUpsert do
  @enforce_keys [:messages, :type]
  defstruct [:messages, :type, :request_id]
end
```

**Step 3: Update converter**

`Irish.Event.convert/2` should return typed structs for known events and keep unknown events as raw maps.

**Step 4: Keep compatibility layer**

Add opt-out flag to preserve current map output (`event_structs: false`) for one minor release.

**Step 5: Verify**

Run: `mix test test/irish/event_test.exs test/irish/event_types_test.exs`
Expected: PASS.

---

### Task 6: Normalize Core Data Structures for Baileys Drift

**Files:**
- Modify: `lib/irish/message.ex`
- Modify: `lib/irish/message_key.ex`
- Modify: `lib/irish/group.ex`
- Modify: `lib/irish/group/participant.ex`
- Modify: `lib/irish/call.ex`
- Create: `lib/irish/coerce.ex`
- Test: `test/irish/message_test.exs`
- Test: `test/irish/group_test.exs`
- Test: `test/irish/call_test.exs`

**Step 1: Add failing tests for shape drift tolerance**

Examples:
- missing/variant numeric fields (`"1700000000"`, `1700000000`, float)
- message reaction event nested shapes
- group participant variants missing `phoneNumber`

**Step 2: Implement coercion utilities**

```elixir
defmodule Irish.Coerce do
  def bool(v), do: v == true
  def int(v) when is_integer(v), do: v
  def int(v) when is_binary(v), do: case Integer.parse(v), do: ({i, _} -> i; :error -> nil)
  def int(_), do: nil
end
```

**Step 3: Apply coercion consistently**

Use `Irish.Coerce` in all `from_raw/1` functions to keep behavior uniform and easy to audit.

**Step 4: Tighten public types**

Replace `any()` in return types with concrete types where possible (e.g., receipt type union, presence type union).

**Step 5: Verify**

Run: `mix test test/irish/message_test.exs test/irish/group_test.exs test/irish/call_test.exs`
Expected: PASS.

---

### Task 7: Improve Public API Ergonomics and Reuse

**Files:**
- Create: `lib/irish/client.ex` (facade for explicit API)
- Modify: `lib/irish.ex`
- Create: `lib/irish/types.ex`
- Test: `test/irish/client_test.exs`

**Step 1: Add failing tests for validations**

Cases:
- invalid JID rejected with `{:error, :invalid_jid}`
- invalid receipt type rejected before bridge call
- empty participant list rejected for group updates

**Step 2: Add public type aliases and guards**

```elixir
@type jid :: String.t()
@type receipt_type :: :read | :"read-self" | :played
```

**Step 3: Validate inputs before bridge calls**

Add private validators in API module and return deterministic errors.

**Step 4: Extract repeated `command` wrappers**

Use a small internal helper:

```elixir
defp call(conn, cmd, args, decoder \\ &{:ok, &1})
```

**Step 5: Verify**

Run: `mix test test/irish/client_test.exs`
Expected: PASS.

---

### Task 8: Add Telemetry for Production Observability

**Files:**
- Modify: `lib/irish/connection.ex`
- Create: `lib/irish/telemetry.ex`
- Test: `test/irish/telemetry_test.exs`
- Update: `README.md`

**Step 1: Write failing telemetry tests**

Capture:
- `[:irish, :command, :start|:stop|:exception]`
- `[:irish, :bridge, :event]`
- `[:irish, :bridge, :reconnect]`

**Step 2: Emit telemetry events around command lifecycle**

Include metadata: `cmd`, `id`, `duration`, `result`.

**Step 3: Emit telemetry for bridge failures/restarts**

Include `exit_status`, `reason`, reconnect count.

**Step 4: Verify**

Run: `mix test test/irish/telemetry_test.exs`
Expected: PASS.

---

### Task 9: Build Realistic Contract Tests for Bridge IO

**Files:**
- Create: `test/support/fake_bridge.ex`
- Create: `test/irish/connection_protocol_integration_test.exs`
- Modify: `test/test_helper.exs`

**Step 1: Write failing integration tests**

Simulate bridge lines:
- valid response resolves pending request
- malformed JSON line does not crash connection
- out-of-order responses still resolve correctly
- event conversion respects `struct_events` option

**Step 2: Add injectable transport behavior**

Define behavior for `send/2` and callback stream to decouple tests from real port.

**Step 3: Update `Irish.Connection` to accept test transport module**

Use option: `transport: Irish.Transport.Port` by default.

**Step 4: Verify**

Run: `mix test test/irish/connection_protocol_integration_test.exs`
Expected: PASS.

---

### Task 10: Documentation and Migration Guide for Stable API

**Files:**
- Modify: `README.md`
- Create: `guides/events.md`
- Create: `guides/migration-0.1-to-0.2.md`
- Create: `CHANGELOG.md`

**Step 1: Write failing doc checks**

Run: `mix docs`
Expected: warnings for missing module docs/guides until files are added.

**Step 2: Document event contracts and compatibility policy**

Include:
- supported Baileys major/minor range
- event conversion guarantees
- unknown event passthrough policy
- deprecation windows

**Step 3: Add migration examples**

Before/after examples for map vs struct event payloads and validation changes.

**Step 4: Verify**

Run: `mix docs`
Expected: docs build cleanly with guides.

---

### Task 11: CI Matrix and Release Discipline

**Files:**
- Modify: `.github/workflows/ci.yml`
- Modify: `.github/workflows/release.yml`
- Create: `.github/dependabot.yml`

**Step 1: Add matrix**

- Elixir versions: latest two supported
- OTP versions: current + previous
- `mix test`, `mix credo --strict`, `mix dialyzer`, `mix docs`

**Step 2: Add bridge smoke test in CI**

Minimal smoke test that validates Deno starts and bridge emits init ack.

**Step 3: Add release checklist job**

Prevent release unless changelog entry and docs are updated.

**Step 4: Verify**

Run locally: `mix test && mix credo --strict && mix dialyzer`
Expected: PASS.

---

### Task 12: Backward-Compatibility and Deprecation Pass

**Files:**
- Modify: `lib/irish.ex`
- Modify: `lib/irish/event.ex`
- Create: `test/irish/backward_compat_test.exs`

**Step 1: Write failing compatibility tests**

Ensure old API paths still function with deprecation warnings.

**Step 2: Add explicit `@deprecated` annotations**

Maintain old options/functions for one minor release.

**Step 3: Add runtime warnings for behavior changes**

Warn when legacy map payload mode is used.

**Step 4: Verify**

Run: `mix test test/irish/backward_compat_test.exs`
Expected: PASS with warning assertions.

---

## Recommended Execution Order (Critical Path)

1. Task 3 (timeout + init handshake)
2. Task 4 (bridge lifecycle hardening)
3. Task 9 (protocol integration tests)
4. Task 5 + Task 6 (event/data contract quality)
5. Task 7 (public API ergonomics)
6. Task 8 (telemetry)
7. Task 1 + Task 11 + Task 10 (publish/release readiness)
8. Task 12 (compatibility/deprecations)

## Verification Gate Before Marking Complete

Run:

```bash
mix format --check-formatted
mix test
mix credo --strict
mix dialyzer
mix docs
```

Expected:
- All commands pass.
- `README.md` and guides reflect final API contracts.
- CI workflows enforce the same checks.

