#!/usr/bin/env bash
# Fake bridge that exercises auth callbacks during init.
#
# Flow:
#   1. Read init command
#   2. Send auth.load_creds request to Elixir, read response
#   3. If no creds, send auth.save_creds with fresh creds
#   4. Send auth.keys_get request, read response
#   5. Send auth.keys_set request, read response
#   6. Respond with init success
#   7. Command loop (same as fake_bridge.sh)

extract_field() {
  echo "$1" | grep -o "\"$2\":\"[^\"]*\"" | head -1 | cut -d'"' -f4
}

# Read init command
read -r line
init_id=$(extract_field "$line" "id")

# --- Auth callback: load_creds ---
echo "{\"v\":1,\"id\":\"br_1\",\"req\":\"auth.load_creds\",\"args\":{}}"
read -r resp

# Check if data is null (no existing creds) — grep for "data":null anywhere in the JSON
if echo "$resp" | grep -q '"data":null'; then
  # No existing creds — save fresh ones
  echo "{\"v\":1,\"id\":\"br_2\",\"req\":\"auth.save_creds\",\"args\":{\"creds\":{\"noiseKey\":\"fresh\",\"signedIdentityKey\":\"fresh\"}}}"
  read -r resp
fi

# --- Auth callback: keys_get ---
echo "{\"v\":1,\"id\":\"br_3\",\"req\":\"auth.keys_get\",\"args\":{\"type\":\"pre-key\",\"ids\":[\"1\",\"2\"]}}"
read -r resp

# --- Auth callback: keys_set ---
echo "{\"v\":1,\"id\":\"br_4\",\"req\":\"auth.keys_set\",\"args\":{\"data\":{\"pre-key\":{\"5\":{\"keyPair\":\"test\"}}}}}"
read -r resp

# Init complete
echo "{\"v\":1,\"id\":\"$init_id\",\"ok\":true,\"data\":{\"status\":\"initialized\"}}"

# Command loop
while IFS= read -r line; do
  id=$(extract_field "$line" "id")
  cmd=$(extract_field "$line" "cmd")

  case "$cmd" in
    "echo")
      args=$(echo "$line" | sed 's/.*"args"://' | sed 's/}$//')
      echo "{\"v\":1,\"id\":\"$id\",\"ok\":true,\"data\":$args}"
      ;;
    *)
      echo "{\"v\":1,\"id\":\"$id\",\"ok\":false,\"error\":{\"code\":\"unknown_command\",\"message\":\"unknown: $cmd\",\"details\":{}}}"
      ;;
  esac
done
