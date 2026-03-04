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
  OPENCLAW_INSTALL_ARGS=(--prefix "$OPENCLAW_PREFIX" --onboard)
fi
curl -fsSL --proto '=https' --tlsv1.2 https://openclaw.ai/install-cli.sh | bash -s -- "${OPENCLAW_INSTALL_ARGS[@]}"

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
