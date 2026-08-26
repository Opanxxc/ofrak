#!/data/data/com.termux/files/usr/bin/env bash
# ==============================================================
#  Runs INSIDE termux/termux-docker:aarch64 container.
#  Compiles OFRAK + deps natively against Bionic/Termux, then
#  packages everything into a Termux-format .deb (aarch64).
#
#  Host mounts repo at /work; output deb copied back to /work/
# ==============================================================
set -euo pipefail

PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PATH"
export HOME="${HOME:-/root}"
export DEBIAN_FRONTEND=noninteractive

echo "[*] Updating Termux packages..."
pkg update -y
pkg upgrade -y

echo "[*] Installing build dependencies..."
pkg install -y \
  python python-pip \
  clang make cmake binutils pkg-config \
  libffi openssl rust git lld \
  ncurses readline zlib dpkg

export CFLAGS="-Wno-deprecated-declarations"
export CPPFLAGS="-I$PREFIX/include"
export LDFLAGS="-L$PREFIX/lib -Wl,-rpath=$PREFIX/lib"
# New setuptools removed pkg_resources which some sdists import at build time
# NOTE: Termux has no writable /tmp - use $HOME instead
printf 'setuptools<81\n' > "$HOME/.pip-constraints.txt"
export PIP_CONSTRAINT="$HOME/.pip-constraints.txt"

echo "[*] Upgrading pip/setuptools/wheel..."
python3 -m pip install --upgrade pip setuptools wheel

echo "[*] Copying sources to writable dir (/work may be read-only)..."
BUILDDIR="$HOME/build"
rm -rf "$BUILDDIR" && mkdir -p "$BUILDDIR"
cp -r /work/ofrak_type /work/ofrak_io /work/ofrak_patch_maker /work/ofrak_core "$BUILDDIR/"
mkdir -p "$HOME/scripts"
cp /work/scripts/ofrak-menu.sh "$HOME/scripts/" 2>/dev/null || true

echo "[*] Compiling & installing OFRAK packages (this takes a while)..."
python3 -m pip install \
  "$BUILDDIR/ofrak_type" \
  "$BUILDDIR/ofrak_io" \
  "$BUILDDIR/ofrak_patch_maker"
python3 -m pip install "$BUILDDIR/ofrak_core"

echo "[*] Verifying install..."
command -v ofrack >/dev/null || { echo "[-] ofrack binary missing"; exit 1; }
ofrak list | head -5 || true

# --- Stage into Termux filesystem layout ----------------------
PYVER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
SP="$PREFIX/lib/python$PYVER/site-packages"
STAGE="$HOME/debstage"
rm -rf "$STAGE"
mkdir -p "$STAGE/data/data/com.termux/files/usr/lib/python$PYVER" \
         "$STAGE/data/data/com.termux/files/usr/bin" \
         "$STAGE/DEBIAN"

echo "[*] Staging site-packages..."
cp -r "$SP" "$STAGE/data/data/com.termux/files/usr/lib/python$PYVER/site-packages"
# Ship the CLI wrapper + terminal UI menu
cp "$PREFIX/bin/ofrak" "$STAGE/data/data/com.termux/files/usr/bin/ofrak"
cp "$HOME/scripts/ofrak-menu.sh" "$STAGE/data/data/com.termux/files/usr/bin/ofrak-menu"
chmod +x "$STAGE/data/data/com.termux/files/usr/bin/ofrak-menu"

cat > "$STAGE/DEBIAN/control" << EOF
Package: ofrak
Version: ${OFRAK_DEB_VERSION}
Section: devel
Priority: optional
Architecture: aarch64
Installed-Size: $(du -sk "$STAGE/data" | cut -f1)
Maintainer: Opanxxc <opanxxc@users.noreply.github.com>
Depends: python (>= ${PYVER}), libffi, openssl, ncurses, readline, zlib
Description: OFRAK - unpack, modify, and repack binaries (Termux build)
 Open Firmware Reverse Analysis Konsole. Binary analysis and
 modification platform with web GUI and Python API.
 Precompiled for Termux aarch64 - no compilation needed.
 Run 'ofrak license --community --i-agree' on first use,
 then 'ofrak gui' and open http://127.0.0.1:8888
Homepage: https://github.com/Opanxxc/ofrak
EOF

echo "[*] Building .deb..."
cd "$HOME"
if dpkg-deb --root-owner-group --build "$STAGE" "ofrak_${OFRAK_DEB_VERSION}_aarch64.deb" 2>/dev/null; then :;
else dpkg-deb --build "$STAGE" "ofrak_${OFRAK_DEB_VERSION}_aarch64.deb"; fi
ls -la "ofrak_${OFRAK_DEB_VERSION}_aarch64.deb"
cp "ofrak_${OFRAK_DEB_VERSION}_aarch64.deb" /work/
echo "[+] DONE: $(ls /work/ofrak_*_aarch64.deb)"
