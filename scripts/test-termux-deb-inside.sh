#!/data/data/com.termux/files/usr/bin/env bash
# ==============================================================
#  Runs INSIDE termux/termux-docker:aarch64 container.
#  AUTO-TEST: installs the built ofrak_*_aarch64.deb into a fresh
#  Termux environment, then verifies CLI + TUI + unpack actually work.
#
#  Host mounts repo at /work (deb must be in /work/)
# ==============================================================
set -euo pipefail

PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PATH"
export HOME="${HOME:-/root}"
export DEBIAN_FRONTEND=noninteractive

PASS=0; FAIL=0
ok()   { echo -e "\033[0;32m[PASS]\033[0m $*"; PASS=$((PASS+1)); }
bad()  { echo -e "\033[0;31m[FAIL]\033[0m $*"; FAIL=$((FAIL+1)); }
check(){ if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi }

echo "[*] Installing runtime deps..."
pkg update -y
pkg install -y python libffi openssl ncurses readline zlib dpkg

DEB=$(ls /work/ofrak_*_aarch64.deb | head -1)
[[ -n "$DEB" ]] || { bad "No .deb found in /work"; exit 1; }
echo "[*] Installing $DEB..."
apt install -y "$DEB" 2>/dev/null || dpkg -i --force-overwrite "$DEB"

echo ""
echo "========== OFRAK TERMUX AUTO-TEST =========="

check "ofrak binary in PATH"          "command -v ofrak"
check "ofrak-menu (TUI) in PATH"      "command -v ofrak-menu"
check "ofrak --help runs"             "ofrak --help"
check "python can import ofrak"       "python3 -c 'import ofrak'"
check "license accept works"          "yes | ofrak license --community --i-agree"
check "ofrak list lists components"   "ofrak list"
check "TUI starts and quits (piped)"  "echo 0 | ofrak-menu"

# Real functional test: unpack a real ELF binary
TESTBIN="$PREFIX/bin/ping"
cp "$TESTBIN" "$HOME/test-binary"
if ofrak unpack -o "$HOME/test-out" "$HOME/test-binary" >/dev/null 2>&1; then
    if [[ -d "$HOME/test-out" ]] && [[ -n "$(ls -A "$HOME/test-out")" ]]; then
        ok "unpack produces output tree ($(ls "$HOME/test-out" | wc -l) entries)"
    else
        bad "unpack ran but output dir empty"
    fi
else
    bad "ofrack unpack failed"
fi

# Verify GUI assets shipped (web frontend files present)
PYVER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
SP="$PREFIX/lib/python$PYVER/site-packages"
check "GUI static assets included"    "test -f '$SP/ofrak/gui/public/index.html'"

echo "============================================="
echo "RESULT: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then exit 1; fi
echo "ALL TERMUX TESTS PASSED ✔"
