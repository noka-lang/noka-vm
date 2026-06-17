#!/usr/bin/env sh
# Build the NokaScript VM core to WebAssembly and copy the artifact into the
# nokascript package so the REPL can load it.

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

# Ship it into the npm package next door.
cp "$here/vm.wasm" "$here/../nokascript/vm.wasm"

echo "successfully built vm.wasm and copied to nokascript/"
