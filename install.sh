#!/bin/sh
# singlet — install the host daemon and start it in the background
# Usage:
#   curl -fsSL https://singlet.xroma.dev/install.sh | sh
#
# Override install location:
#   curl -fsSL https://singlet.xroma.dev/install.sh | PREFIX=/usr/local sh
set -eu

BASE="${SINGLET_URL:-https://singlet.xroma.dev}"
BIN="${SINGLET_BIN_URL:-https://github.com/xavierroma/singlet-host/releases/latest/download}"
VERSION="${SINGLET_VERSION:-latest}"
LABEL="dev.singlet.singletd"

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

statedir="${HOME}/.singlet"
mkdir -p "$statedir"

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
gunzip -f "$tmp/singletd.gz"

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

chmod 755 "$tmp/singletd"
if command -v codesign >/dev/null 2>&1; then
  codesign --sign - --force "$tmp/singletd" >/dev/null 2>&1 || true
fi
xattr -d com.apple.quarantine "$tmp/singletd" 2>/dev/null || true
mv -f "$tmp/singletd" "$bindir/singletd"
rm -f "$bindir/singlet-tui"

# Keep a local copy of uninstall so it still works if the site is down.
fetch "${BIN}/uninstall.sh" "$tmp/uninstall.sh" || \
  fetch "https://xavierroma.github.io/singlet-host/uninstall.sh" "$tmp/uninstall.sh" || \
  fetch "${BASE}/uninstall.sh" "$tmp/uninstall.sh" || true
if [ -f "$tmp/uninstall.sh" ]; then
  chmod 755 "$tmp/uninstall.sh"
  xattr -d com.apple.quarantine "$tmp/uninstall.sh" 2>/dev/null || true
  mv -f "$tmp/uninstall.sh" "$bindir/singlet-uninstall"
fi

case ":$PATH:" in
  *:"$bindir":*) in_path=1 ;;
  *) in_path=0 ;;
esac

info "installed"
printf '    %s\n' "$bindir/singletd"

if [ "$in_path" -eq 0 ]; then
  warn "$bindir is not on PATH. Add this to your shell rc:"
  printf '    export PATH="%s:\$PATH"\n' "$bindir"
fi

# --- background daemon (LaunchAgent) ---
if [ "${SINGLET_NO_SERVICE:-}" = "1" ]; then
  info "SINGLET_NO_SERVICE=1; not starting LaunchAgent"
  exit 0
fi

# A naked CLI cannot prompt for Local Network on modern macOS, so iroh
# mDNS (and sometimes the relay) is silently blocked. Put the binary
# inside an .app so TCC can ask.
app="${HOME}/Applications/Singlet.app"
mkdir -p "$app/Contents/MacOS"
cp "$bindir/singletd" "$app/Contents/MacOS/singletd"
chmod 755 "$app/Contents/MacOS/singletd"
cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>${LABEL}</string>
  <key>CFBundleName</key>
  <string>Singlet</string>
  <key>CFBundleExecutable</key>
  <string>singletd</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSLocalNetworkUsageDescription</key>
  <string>Singlet finds the other half of the pair on your network.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>Singlet carries the voice line between the two keys.</string>
  <key>NSBonjourServices</key>
  <array>
    <string>_irohv1._udp</string>
  </array>
</dict>
</plist>
EOF

plist="${HOME}/Library/LaunchAgents/${LABEL}.plist"
mkdir -p "${HOME}/Library/LaunchAgents"
uid=$(id -u)
daemon_bin="$app/Contents/MacOS/singletd"

cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${daemon_bin}</string>
    <string>run</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>15</integer>
  <key>StandardOutPath</key>
  <string>${statedir}/singletd.log</string>
  <key>StandardErrorPath</key>
  <string>${statedir}/singletd.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key>
    <string>${HOME}</string>
    <key>PATH</key>
    <string>${bindir}:/usr/bin:/bin</string>
  </dict>
</dict>
</plist>
EOF

info "starting daemon in the background"
launchctl bootout "gui/${uid}" "$plist" >/dev/null 2>&1 || true
if launchctl bootstrap "gui/${uid}" "$plist" >/dev/null 2>&1; then
  launchctl enable "gui/${uid}/${LABEL}" >/dev/null 2>&1 || true
  launchctl kickstart -k "gui/${uid}/${LABEL}" >/dev/null 2>&1 || true
else
  launchctl load -w "$plist" >/dev/null 2>&1 || true
fi

sleep 1
if launchctl print "gui/${uid}/${LABEL}" >/dev/null 2>&1 || pgrep -x singletd >/dev/null 2>&1; then
  info "singletd is running (logs: ${statedir}/singletd.log)"
else
  warn "daemon did not stay up — plug in a singlet and check ${statedir}/singletd.log"
fi

cat <<EOF

Plug a singlet into USB if you have not already. Allow Local
Network when macOS asks — without it the two halves cannot find
each other on the LAN. The microphone is used only during a call;
macOS will ask the first time you pick up.

  logs:   ${statedir}/singletd.log
  stop:   launchctl bootout gui/\$(id -u) ~/Library/LaunchAgents/${LABEL}.plist
  remove: curl -fsSL ${BASE}/uninstall.sh | sh

Identity lives in the key, not this computer.

EOF
