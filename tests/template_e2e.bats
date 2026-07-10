#!/usr/bin/env bats

setup_file() {
  command -v zellij >/dev/null || skip "zellij is required"
  command -v python3 >/dev/null || skip "python3 is required"
  local zellij_version
  zellij_version="$(zellij --version | awk '{ print $2 }')"
  [[ "$zellij_version" == 0.45.* ]] || skip "zellij 0.45.x is required by current zellij-tile ABI (found $zellij_version)"
  cargo build --release --target wasm32-wasip1
  export PLUGIN_WASM
  PLUGIN_WASM="$(realpath "$BATS_TEST_DIRNAME/../target/wasm32-wasip1/release/zellij-tabbar.wasm")"
}

setup() {
  TEST_ROOT="$(mktemp -d)"
  SESSION="zellij-tabbar-e2e-${BATS_TEST_NUMBER}-$$-$RANDOM"
  CLIENT_PID=""
}

teardown() {
  zellij kill-session "$SESSION" >/dev/null 2>&1 || true
  if [[ -n "$CLIENT_PID" ]]; then
    kill "$CLIENT_PID" >/dev/null 2>&1 || true
    wait "$CLIENT_PID" 2>/dev/null || true
  fi
  rm -rf "$TEST_ROOT"
}

start_plugin() {
  local template="$1"
  cat >"$TEST_ROOT/layout.kdl" <<KDL
layout {
  tab name="Alpha" {
    pane size=1 borderless=true {
      plugin location="file:$PLUGIN_WASM" {
        template r###"$template"###;
      }
    }
    pane
  }
  tab name="Beta" {
    pane
  }
}
KDL

  mkdir -p "$TEST_ROOT/cache/zellij"
  cat >"$TEST_ROOT/cache/zellij/permissions.kdl" <<KDL
"$PLUGIN_WASM" {
  ReadApplicationState
}
KDL

  env -u ZELLIJ -u ZELLIJ_SESSION_NAME -u ZELLIJ_PANE_ID \
    TERM=xterm-256color XDG_CACHE_HOME="$TEST_ROOT/cache" PTY_LOG="$TEST_ROOT/client.log" \
    python3 "$BATS_TEST_DIRNAME/helpers/pty_client.py" \
    zellij --session "$SESSION" --new-session-with-layout "$TEST_ROOT/layout.kdl" &
  CLIENT_PID=$!

  local panes=""
  for _ in {1..50}; do
    if panes="$(zellij --session "$SESSION" action list-panes 2>/dev/null)" \
      && grep -q '^plugin_' <<<"$panes"; then
      PLUGIN_PANE="$(awk '$2 == "plugin" { print $1; exit }' <<<"$panes")"
      zellij --session "$SESSION" action go-to-tab 1 >/dev/null
      zellij --session "$SESSION" action focus-pane-id "$PLUGIN_PANE" >/dev/null
      zellij --session "$SESSION" action rename-tab Alpha >/dev/null
      return
    fi
    sleep 0.1
  done

  printf 'session failed to start\n%s\n' "$panes" >&2
  cat "$TEST_ROOT/client.log" >&2 2>/dev/null || true
  return 1
}

dump_plugin() {
  local output=""
  for _ in {1..30}; do
    output="$(zellij --session "$SESSION" action dump-screen --pane-id "$PLUGIN_PANE")"
    if [[ -n "$output" ]]; then
      printf '%s\n' "$output"
      return
    fi
    sleep 0.1
  done
  zellij --session "$SESSION" action list-panes >&2 || true
  return 1
}

@test "inline template receives session and tab model" {
  start_plugin 'SESSION={{ session.name }} TABS={% for tab in session.tabs %}[{{ tab.index }}:{{ tab.name }}:{{ tab.active }}]{% endfor %}'

  run dump_plugin

  [ "$status" -eq 0 ]
  [[ "$output" == *"SESSION=$SESSION"* ]]
  [[ "$output" == *"[1:Alpha:true]"* ]]
  [[ "$output" == *"[2:Beta:false]"* ]]
}

@test "Stack and Flex place content at opposite viewport edges" {
  start_plugin '{% call Stack() %}{% call Flex(justify="start") %}LEFT{% endcall %}{% call Flex(justify="end") %}RIGHT{% endcall %}{% endcall %}'

  run dump_plugin

  [ "$status" -eq 0 ]
  [[ "$output" == LEFT* ]]
  [[ "$output" == *RIGHT ]]
}

@test "template errors render in the plugin pane" {
  start_plugin '{{ broken'

  run dump_plugin

  [ "$status" -eq 0 ]
  [[ "$output" == *"template error:"* ]]
}
