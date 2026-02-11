#!/usr/bin/env bash
# Fake bridge for integration testing.
# Handles init, echoes commands back, and can emit events.
#
# Commands:
#   init          → {ok, {status: initialized}}
#   echo          → {ok, args}
#   slow_echo     → sleep 0.5 then {ok, args}
#   fail          → {ok: false, error: {code, message, details}}
#   emit_event    → emits an event then responds ok
#   <other>       → {ok: false, error: unknown_command}

extract_field() {
  echo "$1" | grep -o "\"$2\":\"[^\"]*\"" | head -1 | cut -d'"' -f4
}

# Read init command
read -r line
id=$(extract_field "$line" "id")
echo "{\"id\":\"$id\",\"ok\":true,\"data\":{\"status\":\"initialized\"}}"

# Command loop
while IFS= read -r line; do
  id=$(extract_field "$line" "id")
  cmd=$(extract_field "$line" "cmd")

  case "$cmd" in
    "echo")
      # Echo back the full args
      args=$(echo "$line" | sed 's/.*"args"://' | sed 's/}$//')
      echo "{\"id\":\"$id\",\"ok\":true,\"data\":$args}"
      ;;
    "slow_echo")
      sleep 0.5
      args=$(echo "$line" | sed 's/.*"args"://' | sed 's/}$//')
      echo "{\"id\":\"$id\",\"ok\":true,\"data\":$args}"
      ;;
    "fail")
      echo "{\"id\":\"$id\",\"ok\":false,\"error\":{\"code\":\"test_failure\",\"message\":\"intentional failure\",\"details\":{}}}"
      ;;
    "emit_event")
      # Emit an event then respond
      echo "{\"event\":\"test.event\",\"data\":{\"hello\":\"world\"}}"
      echo "{\"id\":\"$id\",\"ok\":true,\"data\":null}"
      ;;
    *)
      echo "{\"id\":\"$id\",\"ok\":false,\"error\":{\"code\":\"unknown_command\",\"message\":\"unknown: $cmd\",\"details\":{}}}"
      ;;
  esac
done
