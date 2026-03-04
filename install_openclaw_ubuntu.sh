#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[install] %s\n' "$*"
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
TMUX_ENHANCE="${TMUX_ENHANCE:-1}"

log "Updating apt package lists..."
sudo apt-get update

log "Upgrading installed packages..."
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

log "Installing required system packages..."
sudo apt-get install -y curl ca-certificates git build-essential tmux

log "Installing Claude Code (native installer)..."
curl -fsSL https://claude.ai/install.sh | bash

log "Installing OpenClaw into: $OPENCLAW_PREFIX"
OPENCLAW_INSTALL_ARGS=(--prefix "$OPENCLAW_PREFIX" --no-onboard)
if [[ "$OPENCLAW_ONBOARD" == "1" ]]; then
  OPENCLAW_INSTALL_ARGS=(--prefix "$OPENCLAW_PREFIX" --onboard)
fi
curl -fsSL --proto '=https' --tlsv1.2 https://openclaw.ai/install-cli.sh | bash -s -- "${OPENCLAW_INSTALL_ARGS[@]}"

if [[ "$TMUX_ENHANCE" == "1" ]]; then
  TMUX_CONF="$HOME/.tmux.conf"
  TMUX_BEGIN="# >>> openclaw tmux enhancement >>>"

  log "Applying tmux enhancements..."
  if [[ ! -f "$TMUX_CONF" ]]; then
    touch "$TMUX_CONF"
  fi

  if ! grep -Fq "$TMUX_BEGIN" "$TMUX_CONF"; then
    cat >> "$TMUX_CONF" <<'EOF'

# >>> openclaw tmux enhancement >>>
set -g mouse on
set -g history-limit 100000
set -g base-index 1
setw -g pane-base-index 1
setw -g mode-keys vi
set -g renumber-windows on

# Fast splits and config reload
bind r source-file ~/.tmux.conf \; display-message "tmux config reloaded"
bind | split-window -h
bind - split-window -v

# Lean status line for ops sessions
set -g status-interval 5
set -g status-left-length 40
set -g status-right-length 90
set -g status-left "#[fg=green]#S #[default]"
set -g status-right "#[fg=cyan]%Y-%m-%d %H:%M #[default]"
# <<< openclaw tmux enhancement <<<
EOF
  fi

  mkdir -p "$OPENCLAW_PREFIX/bin"
  cat > "$OPENCLAW_PREFIX/bin/openclaw-ops-tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SESSION_NAME="${1:-openclaw-ops}"
OPENCLAW_BIN="${OPENCLAW_BIN:-$(command -v openclaw || true)}"
if [[ -z "$OPENCLAW_BIN" && -x "$HOME/.openclaw/bin/openclaw" ]]; then
  OPENCLAW_BIN="$HOME/.openclaw/bin/openclaw"
fi
if [[ -z "$OPENCLAW_BIN" ]]; then
  echo "openclaw command not found. Ensure ~/.openclaw/bin is in PATH."
  exit 1
fi

if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  exec tmux attach -t "$SESSION_NAME"
fi

tmux new-session -d -s "$SESSION_NAME" -n ops "$OPENCLAW_BIN gateway status --deep; bash"
tmux split-window -h -t "$SESSION_NAME:ops" "$OPENCLAW_BIN health --verbose; bash"
tmux split-window -v -t "$SESSION_NAME:ops.1" "$OPENCLAW_BIN channels status --probe; bash"
tmux split-window -v -t "$SESSION_NAME:ops.2" "$OPENCLAW_BIN logs --follow --local-time"
tmux select-layout -t "$SESSION_NAME:ops" tiled
tmux select-pane -t "$SESSION_NAME:ops.0"

exec tmux attach -t "$SESSION_NAME"
EOF
  chmod +x "$OPENCLAW_PREFIX/bin/openclaw-ops-tmux"
fi

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

log "Done."
log "Next steps:"
log "1) Open a new terminal (or run: source ~/.bashrc)"
log "2) Run: claude"
log "3) Run: openclaw onboard --install-daemon"
log "4) Run: openclaw-ops-tmux (optional tmux ops dashboard)"
