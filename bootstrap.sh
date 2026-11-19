#!/bin/bash
# bootstrap.sh — Rebel Strike (ModernGekko) one-shot setup for a fresh machine
#
# Usage:
#   ./bootstrap.sh              # does everything: box, toolchain, build, configs
#   ./bootstrap.sh --no-box     # assume distrobox already exists, skip creation
#   ./bootstrap.sh --no-build   # toolchain + configs only (skip compile)
#
# Assumes: host has distrobox + podman, repo cloned, ISO placed at iso/rebel_strike.iso
# Safe to re-run: every step is idempotent.

set -euo pipefail

BOX_NAME="decomp-env"
ISO_PATH="iso/rebel_strike.iso"
GAME_SLUG="rebel-strike"

NO_BOX=false
NO_BUILD=false
for arg in "$@"; do
  case "$arg" in
    --no-box)   NO_BOX=true ;;
    --no-build) NO_BUILD=true ;;
  esac
done

step() { echo -e "\n\033[1;35m==> $1\033[0m"; }

# ---------------------------------------------------------------------------
step "Step 0: sanity checks (host side)"
if ! command -v distrobox >/dev/null; then
  echo "ERROR: distrobox not found on host. On Bazzite it is preinstalled; otherwise install it first." >&2
  exit 1
fi
if [ "$NO_BUILD" = false ] && [ ! -f "$ISO_PATH" ]; then
  echo "WARNING: $ISO_PATH not found. Place your legally-owned ISO there before the build step." >&2
  echo "         (continuing — you can re-run later)"
fi

# ---------------------------------------------------------------------------
if [ "$NO_BOX" = false ]; then
  step "Step 1: create distrobox '$BOX_NAME' (Ubuntu 22.04) if missing"
  if distrobox list | grep -qw "$BOX_NAME"; then
    echo "Box '$BOX_NAME' already exists — skipping creation."
  else
    distrobox create --name "$BOX_NAME" --image ubuntu:22.04
  fi
fi

# ---------------------------------------------------------------------------
step "Step 2: toolchain inside the box (LLVM 20 from apt.llvm.org + GCC 13)"
distrobox enter "$BOX_NAME" -- bash -s <<'TOOLEOF'
set -euo pipefail

need_repo=false
if ! apt-cache policy llvm-20 2>/dev/null | grep -q "apt.llvm.org"; then
  need_repo=true
fi

if [ "$need_repo" = true ]; then
  echo "-- adding apt.llvm.org repo for jammy --"
  sudo apt-get update -qq
  sudo apt-get install -y -qq lsb-release wget software-properties-common gnupg
  wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | sudo tee /etc/apt/trusted.gpg.d/apt.llvm.org.asc >/dev/null
  # add both toolchain repo lines for jammy-20
  echo "deb http://apt.llvm.org/jammy/ llvm-toolchain-jammy-20 main" | \
    sudo tee /etc/apt/sources.list.d/llvm20.list >/dev/null
  echo "deb-src http://apt.llvm.org/jammy/ llvm-toolchain-jammy-20 main" | \
    sudo tee -a /etc/apt/sources.list.d/llvm20.list >/dev/null
  sudo apt-get update -qq
fi

echo "-- pinning llvm-toolchain-jammy-20 above other suites (fixes libc++ exact-dep conflicts) --"
sudo tee /etc/apt/preferences.d/llvm-20 >/dev/null <<'PIN'
Package: *
Pin: release n=llvm-toolchain-jammy-20
Pin-Priority: 1100
PIN

echo "-- installing LLVM 20 + GCC 13 --"
sudo apt-get update -qq
sudo apt-get install -y -qq \
  llvm-20 clang-20 lld-20 lldb-20 clangd-20 clang-format-20 clang-tidy-20 \
  clang-tools-20 libclang-20-dev libomp-20-dev \
  libc++-20-dev libc++abi-20-dev python3-clang-20

if ! command -v g++-13 >/dev/null; then
  echo "-- GCC 13 from ubuntu-toolchain-r/test PPA (C++23 support) --"
  sudo add-apt-repository -y ppa:ubuntu-toolchain-r/test
  sudo apt-get update -qq
  sudo apt-get install -y -qq g++-13 gcc-13
fi

echo "-- LLVM 20 version:";   llvm-config-20 --version 2>/dev/null || true
echo "-- GCC 13 version:";    g++-13 --version | head -1
echo "Toolchain OK."
TOOLEOF

# ---------------------------------------------------------------------------
if [ "$NO_BUILD" = false ]; then
  step "Step 3: clean build + first run (extracts ISO, builds interpreter runtime)"
  distrobox enter "$BOX_NAME" -- bash -c "
    set -euo pipefail
    cd '$PWD'
    rm -rf lib/ModernGekko/build vendor/dolphin/DolRecomp/build
    CC=gcc-13 CXX=g++-13 \
    LLVM_ROOT=/usr/lib/llvm-20 CMAKE_PREFIX_PATH=/usr/lib/llvm-20 \
      make run ISO='$ISO_PATH'
  "
  echo "NOTE: compiled module currently gets rejected at runtime (known upstream bug —"
  echo "      see docs/issue-report.md); the runner will fall back to --allow-interpreter"
  echo "      via the launcher script."
fi

# ---------------------------------------------------------------------------
step "Step 4: install tuned configs + distrobox shims"
distrobox enter "$BOX_NAME" -- bash -c "
  set -euo pipefail
  cd '$PWD'
  ./setup-configs.sh
"

# ---------------------------------------------------------------------------
step "Step 5: export host-side launcher (optional if already exported)"
distrobox enter "$BOX_NAME" -- bash -c "
  distrobox-export --bin ~/bin/moderngekko-rebel-strike --export-path ~/.local/bin 2>/dev/null || \\
    echo 'Export already present (or shim missing — run setup-configs.sh first).'
"

echo
echo "=============================================================="
echo " Bootstrap complete!"
echo "   Launch:      moderngekko-rebel-strike          (host, Steam client OPEN for controller)"
echo "   With scale:  moderngekko-rebel-strike --scale fhd   (pillarboxed 2560x1440, 4x internal)"
echo "   Or via:      Steam → add non-Steam game → ~/.local/bin/moderngekko-rebel-strike"
echo "=============================================================="
