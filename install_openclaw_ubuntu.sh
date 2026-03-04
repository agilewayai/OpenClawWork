#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[install] %s\n' "$*"
}

kill_active_tmux_sessions() {
  if ! command -v tmux >/dev/null 2>&1; then
    log "tmux is not installed; skipping tmux session cleanup."
    return 0
  fi

  if ! tmux list-sessions >/dev/null 2>&1; then
    log "No active tmux sessions detected."
    return 0
  fi

  if [[ -z "${TMUX:-}" ]]; then
    log "Active tmux sessions detected; stopping tmux server before installation."
    tmux kill-server >/dev/null 2>&1 || true
    return 0
  fi

  # If installer runs inside tmux, only kill other sessions and keep current.
  local current_session
  local killed_count=0
  current_session="$(tmux display-message -p '#S' 2>/dev/null || true)"
  while IFS= read -r session_name; do
    if [[ -n "$current_session" && "$session_name" == "$current_session" ]]; then
      continue
    fi
    tmux kill-session -t "$session_name" >/dev/null 2>&1 || true
    killed_count=$((killed_count + 1))
  done < <(tmux list-sessions -F '#S' 2>/dev/null || true)

  log "Installer is running inside tmux; killed $killed_count other tmux session(s), kept current session '$current_session'."
}

has_user_systemd() {
  if ! command -v systemctl >/dev/null 2>&1; then
    return 1
  fi
  systemctl --user show-environment >/dev/null 2>&1
}

if [[ "${EUID}" -eq 0 ]]; then
  log "Run this script as a regular user with sudo access (not as root)."
  exit 1
fi

if [[ -r /etc/os-release ]] && ! grep -qi 'ubuntu' /etc/os-release; then
  log "Warning: this script is written for Ubuntu."
fi

OPENCLAW_PREFIX="${OPENCLAW_PREFIX:-$HOME/.openclaw}"
OPENCLAW_ONBOARD="${OPENCLAW_ONBOARD:-0}"
KILL_TMUX_SESSIONS="${KILL_TMUX_SESSIONS:-1}"

if [[ "$KILL_TMUX_SESSIONS" == "1" ]]; then
  kill_active_tmux_sessions
else
  log "Skipping tmux session cleanup (KILL_TMUX_SESSIONS=$KILL_TMUX_SESSIONS)."
fi

log "Updating apt package lists..."
sudo apt-get update

log "Upgrading installed packages..."
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

log "Installing required system packages..."
sudo apt-get install -y curl ca-certificates git build-essential

log "Installing Claude Code (native installer)..."
curl -fsSL https://claude.ai/install.sh | bash

log "Installing OpenClaw into: $OPENCLAW_PREFIX"
OPENCLAW_INSTALL_ARGS=(--prefix "$OPENCLAW_PREFIX" --no-onboard)
if [[ "$OPENCLAW_ONBOARD" == "1" ]]; then
  if has_user_systemd; then
    OPENCLAW_INSTALL_ARGS=(--prefix "$OPENCLAW_PREFIX" --onboard)
  else
    log "OPENCLAW_ONBOARD=1 requested, but user-systemd is unavailable. Falling back to --no-onboard."
  fi
fi
curl -fsSL --proto '=https' --tlsv1.2 https://openclaw.ai/install-cli.sh | bash -s -- "${OPENCLAW_INSTALL_ARGS[@]}"

mkdir -p "$OPENCLAW_PREFIX/bin"

log "Removing legacy tmux integration artifacts (if present)..."
rm -f "$OPENCLAW_PREFIX/bin/openclaw-config-tmux" "$OPENCLAW_PREFIX/bin/openclaw-ops-tmux"
TMUX_CONF="$HOME/.tmux.conf"
TMUX_BEGIN="# >>> openclaw tmux enhancement >>>"
TMUX_END="# <<< openclaw tmux enhancement <<<"
if [[ -f "$TMUX_CONF" ]] && grep -Fq "$TMUX_BEGIN" "$TMUX_CONF"; then
  TMP_TMUX_CONF="$(mktemp -t openclaw-tmux-clean.XXXXXX.conf)"
  awk -v start="$TMUX_BEGIN" -v end="$TMUX_END" '
    $0 == start { skip = 1; next }
    $0 == end { skip = 0; next }
    skip == 0 { print }
  ' "$TMUX_CONF" > "$TMP_TMUX_CONF"
  mv "$TMP_TMUX_CONF" "$TMUX_CONF"
fi

cat > "$OPENCLAW_PREFIX/bin/openclaw-config-safe" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

OPENCLAW_BIN="${OPENCLAW_BIN:-$(command -v openclaw || true)}"
if [[ -z "$OPENCLAW_BIN" && -x "$HOME/.openclaw/bin/openclaw" ]]; then
  OPENCLAW_BIN="$HOME/.openclaw/bin/openclaw"
fi
if [[ -z "$OPENCLAW_BIN" ]]; then
  echo "[openclaw-config] openclaw command not found. Ensure ~/.openclaw/bin is in PATH."
  exit 1
fi

log() {
  printf '[openclaw-config] %s\n' "$*"
}

has_user_systemd() {
  if ! command -v systemctl >/dev/null 2>&1; then
    return 1
  fi
  systemctl --user show-environment >/dev/null 2>&1
}

TMP_LOG="$(mktemp -t openclaw-config.XXXXXX.log)"
trap 'rm -f "$TMP_LOG"' EXIT

log "Running interactive configure wizard..."
set +e
"$OPENCLAW_BIN" configure "$@" 2>&1 | tee "$TMP_LOG"
CONFIG_RC=${PIPESTATUS[0]}
set -e

if [[ "$CONFIG_RC" -eq 0 ]]; then
  log "Configuration finished."
  exit 0
fi

if grep -Eqi 'systemctl( --user)? is-enabled unavailable|systemctl --user is-enabled|failed to connect to bus|Failed to start CLI' "$TMP_LOG"; then
  if has_user_systemd; then
    log "Detected systemd user manager, but configure still failed."
    log "Review output above and retry: $OPENCLAW_BIN configure"
    exit "$CONFIG_RC"
  fi

  GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
  log "No usable user-systemd detected; applying local-mode fallback."
  "$OPENCLAW_BIN" config set gateway.mode local || true
  "$OPENCLAW_BIN" config set gateway.host 127.0.0.1 || true
  "$OPENCLAW_BIN" config set gateway.port "$GATEWAY_PORT" || true

  cat <<EOT
[openclaw-config] Fallback applied: gateway.mode=local
[openclaw-config] Start gateway manually in foreground:
  $OPENCLAW_BIN gateway --port $GATEWAY_PORT
EOT
  exit 0
fi

log "configure failed with exit code $CONFIG_RC."
log "Retry manually with: $OPENCLAW_BIN configure"
exit "$CONFIG_RC"
EOF
chmod +x "$OPENCLAW_PREFIX/bin/openclaw-config-safe"

export PATH="$OPENCLAW_PREFIX/bin:$PATH"
PATH_LINE="export PATH=\"$OPENCLAW_PREFIX/bin:\$PATH\""

for rc_file in "$HOME/.bashrc" "$HOME/.zshrc"; do
  if [[ ! -f "$rc_file" ]]; then
    touch "$rc_file"
  fi
  if ! grep -Fqx "$PATH_LINE" "$rc_file"; then
    printf '\n%s\n' "$PATH_LINE" >> "$rc_file"
  fi
done

log "Installation checks..."
if command -v claude >/dev/null 2>&1; then
  claude --version || true
else
  log "claude command not found in current shell. Open a new terminal and run: claude --version"
fi

if [[ -x "$OPENCLAW_PREFIX/bin/openclaw" ]]; then
  "$OPENCLAW_PREFIX/bin/openclaw" --version || true
else
  log "openclaw binary not found at $OPENCLAW_PREFIX/bin/openclaw"
fi

SYSTEMD_USER_AVAILABLE=0
if has_user_systemd; then
  SYSTEMD_USER_AVAILABLE=1
fi

log "Done."
log "Next steps:"
log "1) Open a new terminal (or run: source ~/.bashrc)"
log "2) Run: claude"
log "3) Run: openclaw-config-safe (recommended first-time configure)"
if [[ "$SYSTEMD_USER_AVAILABLE" == "1" ]]; then
  log "4) Optional daemon mode: openclaw onboard --install-daemon"
else
  log "4) user-systemd unavailable; use local mode (handled by openclaw-config-safe)"
fi
