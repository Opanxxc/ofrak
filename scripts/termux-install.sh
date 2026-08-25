#!/data/data/com.termux/files/usr/bin/env bash
# ==============================================================
#  OFRAK Termux Installer
#  Install OFRAK binary analysis platform on Android via Termux
#
#  Usage:
#    bash termux-install.sh                 # install from PyPI
#    bash termux-install.sh --source <dir>  # install from local fork checkout
# ==============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

info()  { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
die()   { echo -e "${RED}[-] $*${NC}"; exit 1; }

# --- Sanity checks -------------------------------------------
if [[ "${PREFIX:-}" != *"com.termux"* ]]; then
  die "This script must be run inside Termux (Android). PREFIX=$PREFIX"
fi

SRC_MODE=""
if [[ "${1:-}" == "--source" ]]; then
  [[ -n "${2:-}" ]] || die "--source requires a directory argument"
  SRC_MODE="$(realpath "$2")"
  [[ -f "$SRC_MODE/ofrak_core/setup.py" ]] || die "Not an ofrak source tree: $SRC_MODE"
fi

echo "=============================================="
echo "   OFRAK installer for Termux (Android)"
echo "=============================================="

# --- System packages -----------------------------------------
info "Updating Termux packages..."
pkg update -y

info "Installing build dependencies (this may take a while)..."
pkg install -y \
  python python-pip \
  clang make cmake binutils pkg-config \
  libffi openssl rust git patchelf \
  ncurses readline zlib

# --- Build environment tweaks for Termux ---------------------
export CFLAGS="${CFLAGS:-} -Wno-deprecated-declarations"
export LDFLAGS="${LDFLAGS:-} -L$PREFIX/lib"
export CPPFLAGS="${CPPFLAGS:-} -I$PREFIX/include"

info "Upgrading pip/setuptools/wheel..."
pip install --upgrade pip setuptools wheel

# --- Install OFRAK -------------------------------------------
if [[ -n "$SRC_MODE" ]]; then
  info "Installing OFRAK packages from local source: $SRC_MODE"
  pip install "$SRC_MODE/ofrak_type" \
              "$SRC_MODE/ofrak_io" \
              "$SRC_MODE/ofrak_patch_maker"
  pip install "$SRC_MODE/ofrak_core"
else
  info "Installing OFRAK from PyPI..."
  pip install ofrak
fi

# --- License acceptance hint ---------------------------------
info "Accepting community license automatically is NOT done for you."
warn "Run this once after install:  ofrak license --community --i-agree"

# --- Verify ---------------------------------------------------
if command -v ofrak >/dev/null 2>&1; then
  info "OFRAK installed successfully!"
  echo "
==============================================================
 Usage:
   ofrak license --community --i-agree    # first run only
   ofrak gui                              # web GUI on port 8888
   ofrak list                             # list all components

 GUI: open http://127.0.0.1:8888 in your phone browser
=============================================================="
else
  die "ofrak binary not found in PATH. Check pip output above."
fi
