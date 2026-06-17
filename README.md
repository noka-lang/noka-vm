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
```sh
sh build.sh          # compile vm.wasm here
sh build.sh --sync   # compile and copy artifact into a sibling directory (for local testing)
```

### Releasing

Shipping `vm.wasm` to [`nokascript`](https://github.com/noka-lang/nokascript) is
automated. Push a version tag:

```sh
git tag v0.1.0
git push origin v0.1.0
```

CI will open a pull request into [`nokascript`](https://github.com/noka-lang/nokascript). Review and merge that PR to ship.
