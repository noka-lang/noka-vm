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
sh build.sh
```

This compiles `vm.wasm` in the working directory and copies it to `../nokascript/vm.wasm`. 

> ⚠️ TODO: replace this with CI/CD automation!
