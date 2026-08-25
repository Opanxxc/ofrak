#!/data/data/com.termux/files/usr/bin/env bash
# ==============================================================
#  OFRAK Termux Installer
#  FAST PATH (default): download & install prebuilt .deb  (~1 min)
#  SLOW PATH (--source / fallback): compile from source   (~40 min)
#
#  Usage:
#    bash termux-install.sh                 # prebuilt .deb (default)
#    bash termux-install.sh --source <dir>  # build from local checkout
#    bash termux-install.sh --build         # force on-device compile from PyPI
# ==============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

info()  { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
die()   { echo -e "${RED}[-] $*${NC}"; exit 1; }

REPO="Opanxxc/ofrak"

if [[ "${PREFIX:-}" != *"com.termux"* ]]; then
  die "This script must be run inside Termux (Android). PREFIX=$PREFIX"
fi

MODE="${1:-}"
SRC_MODE=""
FORCE_BUILD=0
case "$MODE" in
  --source) [[ -n "${2:-}" ]] || die "--source requires a directory argument"
            SRC_MODE="$(realpath "$2")"
            [[ -f "$SRC_MODE/ofrak_core/setup.py" ]] || die "Not an ofrak source tree: $SRC_MODE" ;;
  --build)  FORCE_BUILD=1 ;;
esac

echo "=============================================="
echo "   OFRAK installer for Termux (Android)"
echo "=============================================="

ARCH=$(uname -m)
[[ "$ARCH" == "aarch64" || "$ARCH" == "armv8"* ]] || warn "Unexpected arch: $ARCH (prebuilt deb is aarch64)"

install_source_build() {
  warn "Falling back to on-device compile (this takes ~30-60 min)..."
  pkg update -y
  pkg install -y python python-pip clang make cmake binutils pkg-config \
                 libffi openssl rust git lld ncurses readline zlib
  export CFLAGS="-Wno-deprecated-declarations"
  export CPPFLAGS="-I$PREFIX/include"
  export LDFLAGS="-L$PREFIX/lib"
  pip install --upgrade pip setuptools wheel
  if [[ -n "$SRC_MODE" ]]; then
    pip install "$SRC_MODE/ofrak_type" "$SRC_MODE/ofrak_io" "$SRC_MODE/ofrak_patch_maker"
    pip install "$SRC_MODE/ofrak_core"
  else
    pip install ofrak
  fi
}

install_prebuilt_deb() {
  info "Fetching latest prebuilt Termux .deb..."
  local API="https://api.github.com/repos/$REPO/releases/tags/continuous"
  local URL
  URL=$(curl -sfL "$API" | grep '"browser_download_url"' | cut -d'"' -f4 | grep '_aarch64\.deb$' | head -1) || true
  [[ -n "$URL" ]] || { warn "No aarch64 .deb asset found in continuous release"; return 1; }

  info "Downloading: $URL"
  curl -fL --retry 3 -o /tmp/ofrak-termux.deb "$URL" || return 1

  # Runtime deps for the prebuilt package
  pkg install -y python libffi openssl ncurses readline zlib dpkg || return 1

  info "Installing .deb..."
  apt install -y /tmp/ofrak-termux.deb || dpkg -i /tmp/ofrak-termux.deb || {
    warn ".deb install failed"; rm -f /tmp/ofrak-termux.deb; return 1;
  }
  rm -f /tmp/ofrak-termux.deb
  return 0
}

if [[ -n "$SRC_MODE" ]]; then
  install_source_build
elif [[ $FORCE_BUILD -eq 1 ]]; then
  install_source_build
else
  if ! install_prebuilt_deb; then
    install_source_build
  fi
fi

# --- License hint + verify ------------------------------------
command -v ofrak >/dev/null 2>&1 || die "ofrak binary not found in PATH. Check output above."

info "OFRAK installed successfully!"
warn "Accept the community license once:  ofrak license --community --i-agree"
cat <<EOF

==============================================================
 Usage:
   ofrak license --community --i-agree    # first run only
   ofrak gui                              # web GUI on port 8888
   ofrak list                             # list all components

 GUI: open http://127.0.0.1:8888 in your phone browser
==============================================================
EOF
