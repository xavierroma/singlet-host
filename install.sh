#!/bin/sh
# singlet — install the host daemon
# Usage:
#   curl -fsSL https://singlet.xroma.dev/install.sh | sh
#
# Override install location:
#   curl -fsSL https://singlet.xroma.dev/install.sh | PREFIX=/usr/local sh
set -eu

BASE="${SINGLET_URL:-https://singlet.xroma.dev}"
# Prebuilt binaries (gzipped). Override to test a preview.
BIN="${SINGLET_BIN_URL:-https://github.com/xavierroma/singlet-host/releases/latest/download}"
VERSION="${SINGLET_VERSION:-latest}"

info()  { printf '==> %s\n' "$*"; }
warn()  { printf 'warn: %s\n' "$*" >&2; }
fail()  { printf 'error: %s\n' "$*" >&2; exit 1; }

os=$(uname -s | tr '[:upper:]' '[:lower:]')
arch=$(uname -m)
case "$os-$arch" in
  darwin-arm64)  triple="macos-arm64" ;;
  darwin-aarch64) triple="macos-arm64" ;;
  *)
    fail "no prebuilt daemon for $os/$arch (need macOS Apple Silicon).
Build from source:
  git clone https://github.com/xavierroma/singlet
  cargo build --release -p singletd --features audio"
    ;;
esac

if [ -n "${PREFIX:-}" ]; then
  bindir="$PREFIX/bin"
elif [ -w /usr/local/bin ] 2>/dev/null; then
  bindir="/usr/local/bin"
else
  bindir="${HOME}/.local/bin"
fi
mkdir -p "$bindir"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT HUP

info "singlet ${VERSION} (${triple}) → ${bindir}"

fetch() {
  src="$1"
  dst="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$src" -o "$dst"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$dst" "$src"
  else
    fail "need curl or wget"
  fi
}

fetch "${BIN}/SHA256SUMS" "$tmp/SHA256SUMS"
fetch "${BIN}/singletd.gz" "$tmp/singletd.gz"
fetch "${BIN}/singlet-tui.gz" "$tmp/singlet-tui.gz"
gunzip -f "$tmp/singletd.gz" "$tmp/singlet-tui.gz"

info "verifying checksums"
(
  cd "$tmp"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -c SHA256SUMS
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c SHA256SUMS
  else
    warn "no shasum/sha256sum; skipping checksum"
  fi
)

chmod 755 "$tmp/singletd" "$tmp/singlet-tui"
# Ad-hoc sign + drop quarantine so Gatekeeper doesn't block a curl-installed CLI.
if command -v codesign >/dev/null 2>&1; then
  codesign --sign - --force "$tmp/singletd" >/dev/null 2>&1 || true
  codesign --sign - --force "$tmp/singlet-tui" >/dev/null 2>&1 || true
fi
xattr -d com.apple.quarantine "$tmp/singletd" 2>/dev/null || true
xattr -d com.apple.quarantine "$tmp/singlet-tui" 2>/dev/null || true
mv -f "$tmp/singletd" "$bindir/singletd"
mv -f "$tmp/singlet-tui" "$bindir/singlet-tui"

case ":$PATH:" in
  *:"$bindir":*) in_path=1 ;;
  *) in_path=0 ;;
esac

info "installed"
printf '    %s\n    %s\n' "$bindir/singletd" "$bindir/singlet-tui"

if [ "$in_path" -eq 0 ]; then
  warn "$bindir is not on PATH. Add this to your shell rc:"
  printf '    export PATH="%s:\$PATH"\n' "$bindir"
fi

cat <<EOF

Plug a singlet into USB, then:

    singletd run

First launch asks for microphone access — allow it.
Identity lives in the key, not this computer. Any Mac running
singletd will find the other half.

EOF
