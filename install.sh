#!/bin/sh
# frostmourne node: install (or update) fm-node from the latest signed release, have systemd keep it
# running across reboots, and print the address and pairing code to add it in the app.
#
#   curl -fsSL https://raw.githubusercontent.com/xacce/frostmourne-releases/main/install.sh | sh
#
# Run it as the user the node should run as (not through sudo); it uses sudo itself where needed.
# Needs: x86-64 Linux with systemd (Ubuntu 24.04 is the reference), curl or wget, openssl, sha256sum.
set -eu

FEED=https://github.com/xacce/frostmourne-releases/releases/latest/download
TARGET=linux-x64
BINS="fm-node fm-keep fm"
D="$HOME/.local/share/frostmourne/bin"
U=frostmourne-node.service
PORT=7710
# The release key's public half (the same one compiled into every frostmourne binary).
KEY='-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAdFu0oiVnpnCfZ/3Eon/UVA3gk+6Y1LPo/TDG+VwfAaY=
-----END PUBLIC KEY-----'

step() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

step "Checking this machine"
[ "$(uname -s)" = Linux ] || die "not Linux ($(uname -s))"
case "$(uname -m)" in x86_64|amd64) ;; *) die "only x86-64 is released, this is $(uname -m)" ;; esac
command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ] || die "systemd is not running here; start the node by hand with: $D/fm-node up"
for c in openssl sha256sum; do command -v "$c" >/dev/null 2>&1 || die "$c is not installed (Ubuntu: sudo apt-get install -y $c)"; done
if command -v curl >/dev/null 2>&1; then dl() { curl -fsSL --retry 2 -o "$2" "$1"; }
elif command -v wget >/dev/null 2>&1; then dl() { wget -q -O "$2" "$1"; }
else die "neither curl nor wget is installed (Ubuntu: sudo apt-get install -y curl)"; fi
if [ "$(id -u)" = 0 ]; then SU=root; su_() { "$@"; }
elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then SU=sudo; su_() { sudo -n "$@"; }
# Piped into sh, stdin is the script: a password prompt goes to the terminal, if there is one.
elif command -v sudo >/dev/null 2>&1 && (: </dev/tty) 2>/dev/null && sudo -v </dev/tty; then SU=sudo; su_() { sudo "$@" </dev/tty; }
else SU=none; fi
echo "user $(id -un), admin rights: $SU"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

step "Fetching the latest release"
dl "$FEED/manifest.json" "$T/manifest.json" || die "cannot download $FEED/manifest.json"
dl "$FEED/manifest.json.sig" "$T/manifest.json.sig" || die "cannot download the release signature"
printf '%s\n' "$KEY" > "$T/key.pem"
openssl pkeyutl -verify -pubin -inkey "$T/key.pem" -rawin -in "$T/manifest.json" -sigfile "$T/manifest.json.sig" >/dev/null 2>&1 \
  || die "the release is NOT signed by the frostmourne release key; nothing was installed"
VERSION=$(sed -n 's/.*"version":"\([^"]*\)".*/\1/p' "$T/manifest.json")
echo "release $VERSION, signature OK"

step "Installing to $D"
mkdir -p "$D"
# One file entry a line: {"name":..,"target":..,"url":..,"size":..,"sha256":..}
tr '{' '\n' < "$T/manifest.json" > "$T/entries"
CHANGED=no
for b in $BINS; do
  e=$(grep "\"name\":\"$b\",\"target\":\"$TARGET\"" "$T/entries" || true)
  [ -n "$e" ] || die "release $VERSION has no $b for $TARGET"
  url=$(printf '%s' "$e" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')
  sha=$(printf '%s' "$e" | sed -n 's/.*"sha256":"\([0-9a-f]*\)".*/\1/p')
  case "$url" in https://*) ;; *) die "bad url for $b: $url" ;; esac
  if [ -f "$D/$b" ] && [ "$(sha256sum "$D/$b" | cut -d' ' -f1)" = "$sha" ]; then echo "$b: up to date"; continue; fi
  dl "$url" "$D/$b.new" || die "cannot download $url"
  [ "$(sha256sum "$D/$b.new" | cut -d' ' -f1)" = "$sha" ] || { rm -f "$D/$b.new"; die "$b: checksum mismatch"; }
  chmod 755 "$D/$b.new"
  mv -f "$D/$b.new" "$D/$b"
  echo "$b: installed"
  CHANGED=yes
done

step "Autostart (systemd)"
if [ "$SU" = none ]; then
  WANTED=default.target; WHO=""
else
  WANTED=multi-user.target; WHO="User=$(id -un)"
fi
cat > "$T/$U" <<EOF
[Unit]
Description=frostmourne node (fm-node)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
$WHO
ExecStart=$D/fm-node up
ExecStop=$D/fm-node stop
TimeoutStartSec=60

[Install]
WantedBy=$WANTED
EOF
if [ "$SU" = none ]; then
  echo "no admin rights: a user service, kept running without a login (linger)"
  mkdir -p "$HOME/.config/systemd/user"
  mv -f "$T/$U" "$HOME/.config/systemd/user/$U"
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  loginctl enable-linger "$(id -un)" 2>/dev/null || [ "$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null)" = yes ] \
    || die "cannot keep the node running after logout: ask an admin to run 'sudo loginctl enable-linger $(id -un)' once, then run this again"
  sc() { systemctl --user "$@"; }
  logs() { journalctl --user -u "$U" -n 30 --no-pager >&2 2>/dev/null || true; }
else
  su_ install -m 644 "$T/$U" "/etc/systemd/system/$U"
  sc() { su_ systemctl "$@"; }
  logs() { su_ journalctl -u "$U" -n 30 --no-pager >&2 || true; }
  if command -v ufw >/dev/null 2>&1 && su_ ufw status 2>/dev/null | grep -q "Status: active"; then
    su_ ufw allow "$PORT/tcp" >/dev/null && echo "firewall (ufw): TCP $PORT opened"
  fi
fi
sc daemon-reload
sc enable --quiet "$U"
if [ "$CHANGED" = yes ] || ! sc is-active --quiet "$U"; then
  # A node from older binaries ends first (its chats with it).
  sc stop "$U" >/dev/null 2>&1 || true
  "$D/fm-node" stop >/dev/null 2>&1 || true
  sc start "$U" || { logs; die "the service did not start (log above)"; }
fi
sc is-active --quiet "$U" || { logs; die "the service did not stay up (log above)"; }
echo "service $U: enabled at boot, running"

step "Pairing"
CODE=$("$D/fm-node" code | tail -n 1)
[ -n "$CODE" ] || die "fm-node gave no pairing code"
ADDRS=$(hostname -I 2>/dev/null || true)
echo "frostmourne node $VERSION is up on port $PORT."
echo
echo "In the app: Settings -> Nodes -> Add a node, then enter"
for a in $ADDRS; do case "$a" in *:*) ;; *) echo "  address: $a:$PORT" ;; esac; done
[ -n "$ADDRS" ] || echo "  address: <this server's address>:$PORT"
echo "  code:    $CODE      (valid 10 minutes; a new one: $D/fm-node code)"
echo
echo "TCP $PORT must be reachable from the app's machine (cloud firewall / security group too)."
