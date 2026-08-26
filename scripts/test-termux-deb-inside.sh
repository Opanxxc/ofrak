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
check(){ if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; echo "    debug:"; eval "$2" 2>&1 | head -10; fi }

echo "[*] Configuring official repo..."
mkdir -p "$PREFIX/etc/apt/sources.list.d"
rm -f "$PREFIX/etc/apt/sources.list.d/"*.list
cat > "$PREFIX/etc/apt/sources.list" << 'REPO'
deb https://packages.termux.org/apt/termux-main stable main
REPO

pkg update -y 2>/dev/null || true
pkg install -y python python-pip libffi openssl ncurses readline zlib dpkg rust binutils 2>/dev/null || \
  apt-get install -y python python-pip libffi openssl ncurses readline zlib dpkg rust binutils 2>/dev/null || true

# Upgrade pip/setuptools before installing deb
export PIP_CONSTRAINT="$HOME/.pip-constraints.txt"
printf 'setuptools<81\n' > "$HOME/.pip-constraints.txt" 2>/dev/null || true
python3 -m pip install --upgrade pip setuptools wheel 2>/dev/null || true

DEB=$(ls /work/ofrak_*_aarch64.deb 2>/dev/null | head -1)
[[ -n "$DEB" ]] || { bad "No .deb found in /work"; exit 1; }
echo "[*] Installing $DEB..."
apt install -y "$DEB" 2>/dev/null || dpkg -i --force-overwrite "$DEB" 2>/dev/null || \
  dpkg --force-all -i "$DEB" 2>/dev/null || { bad "dpkg install failed"; exit 1; }

echo "[*] Installing maturin + cryptography (optional, for license verification)..."
python3 -m pip install --no-cache-dir maturin 2>&1 | tail -3 || true
python3 -m pip install --no-cache-dir cffi cryptography 2>&1 | tail -5 || \
  echo "[i] cryptography skipped - ofrak works without it (lazy import)"

echo ""
echo "========== OFRAK TERMUX AUTO-TEST =========="

# Show what's in site-packages for debugging
PYVER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo '3.14')
SP_DIR="$PREFIX/lib/python$PYVER/site-packages"
echo "[*] site-packages: $(ls "$SP_DIR" 2>/dev/null | wc -l) entries"
echo "[*] ofrak dir exists: $(test -d "$SP_DIR/ofrak" && echo YES || echo NO)"
echo "[*] Full import traceback:"
python3 -c 'import ofrak' 2>&1 | head -15 || true
echo "[*] ofrak binary: $(readlink -f "$(command -v ofrak 2>/dev/null)" 2>/dev/null || echo 'N/A')"

check "ofrak binary in PATH"          "command -v ofrak"
check "ofrak-menu (TUI) in PATH"      "command -v ofrak-menu"
check "python can import ofrak"       "python3 -c 'import ofrak'"
check "ofrak --help runs"             "ofrak --help"
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
    bad "ofrak unpack failed"
fi

# Verify GUI assets shipped (web frontend files present)
check "GUI static assets included"    "test -f '$SP_DIR/ofrak/gui/public/index.html'"

echo "============================================="
echo "RESULT: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then exit 1; fi
echo "ALL TERMUX TESTS PASSED ✔"
