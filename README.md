<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark-mode.png">
  <source media="(prefers-color-scheme: light)" srcset="assets/logo-light-mode.png">
  <img alt="Noka" src="assets/logo-default.png">
</picture>

Zig source for the **NokaScript** VM core. Compiles to `vm.wasm`, which is
shipped inside the [`nokascript`](https://www.npmjs.com/package/nokascript) npm package. 

> ⚠️ End users do not need Zig to use Noka/NokaScript! This repo is for core development only.

---

### Build

Requires Zig 0.16.0.

```sh
zig build                  # build the native debug runner (zig-out/bin/noka)
zig build run -- '1 + 2'   # evaluate a program natively
zig build test             # run the unit tests
zig build wasm             # build the shipped artifact at zig-out/vm.wasm
```

`zig build run` reads from stdin when given no argument, so `cat foo.noka | zig
build run` works too.

### Releasing

Shipping `vm.wasm` to [`nokascript`](https://github.com/noka-lang/nokascript) is
automated. Push a version tag:

```sh
git tag v0.1.0
git push origin v0.1.0
```

CI will open a pull request into [`nokascript`](https://github.com/noka-lang/nokascript). Review and merge that PR to ship.
