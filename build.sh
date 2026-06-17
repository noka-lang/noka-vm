#!/usr/bin/env sh
# Build the NokaScript VM core to WebAssembly.
#
# Usage:
#   sh build.sh           Build vm.wasm in this directory.
#   sh build.sh --sync    Also copy it into a sibling nokascript checkout
#                         (../nokascript/src/core/vm.wasm) for local testing.
#
# Releasing is automated: push a version tag and CI builds vm.wasm, attaches it
# to a GitHub Release, and opens a PR into nokascript. See
# .github/workflows/release.yml. You only need --sync for quick local iteration.

set -e

here=$(cd "$(dirname "$0")" && pwd)

zig build-exe "$here/vm.zig" \
  -target wasm32-freestanding \
  -fno-entry \
  -O ReleaseSmall \
  --export=init \
  --export=interpret \
  --export=scratch_ptr \
  --export=scratch_cap \
  -femit-bin="$here/vm.wasm"

echo "built vm.wasm"

if [ "$1" = "--sync" ]; then
  dest="$here/../nokascript/src/core/vm.wasm"
  cp "$here/vm.wasm" "$dest"
  echo "synced to $dest"
fi
