#!/bin/sh
# singlet — stop the background daemon and remove the install
# Usage:
#   curl -fsSL https://singlet.xroma.dev/uninstall.sh | sh
set -eu

LABEL="dev.singlet.singletd"

info() { printf '==> %s\n' "$*"; }
warn() { printf 'warn: %s\n' "$*" >&2; }

uid=$(id -u)
plist="${HOME}/Library/LaunchAgents/${LABEL}.plist"

info "stopping daemon"
if [ -f "$plist" ]; then
  launchctl bootout "gui/${uid}" "$plist" >/dev/null 2>&1 || \
    launchctl unload -w "$plist" >/dev/null 2>&1 || true
  rm -f "$plist"
fi
# Catch a leftover process from an older nohup install.
pkill -x singletd >/dev/null 2>&1 || true

remove_bin() {
  dir="$1"
  [ -d "$dir" ] || return 0
  for name in singletd singlet-tui singlet-uninstall; do
    path="${dir}/${name}"
    if [ -e "$path" ]; then
      info "removing $path"
      rm -f "$path"
    fi
  done
}

if [ -n "${PREFIX:-}" ]; then
  remove_bin "$PREFIX/bin"
fi
remove_bin "${HOME}/.local/bin"
remove_bin "/usr/local/bin"

app="${HOME}/Applications/Singlet.app"
if [ -d "$app" ]; then
  info "removing $app"
  rm -rf "$app"
fi

if [ "${SINGLET_PURGE:-}" = "1" ]; then
  if [ -d "${HOME}/.singlet" ]; then
    info "removing ${HOME}/.singlet"
    rm -rf "${HOME}/.singlet"
  fi
else
  info "left ${HOME}/.singlet (logs). Purge with SINGLET_PURGE=1"
fi

info "uninstalled"
