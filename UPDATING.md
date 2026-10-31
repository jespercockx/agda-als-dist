# Updating for a new Agda release

This runbook is mechanical by design: a new Agda release should require editing
one config file, running the build, and pushing a tag. Artifacts are attached
to a GitHub Release by CI; they are never committed.

## The moving parts

A build brings together four pinned inputs, all recorded in
`config/version.env` on `main`:

| Input | Where it is pinned | Notes |
| --- | --- | --- |
| Agda Language Server | `ALS_REVISION` | `agda-web/agda-language-server` |
| Agda | `AGDA_REVISION` | `agda-web/agda` (WASM mirror of `agda/agda`) |
| ghc-wasm-meta | `GHC_WASM_META_REVISION`, `GHC_WASM_META_FLAVOUR` | `ghc/ghc-wasm-meta` |
| entropy patch version | `ENTROPY_VERSION` | only the cross-compile patch is ours |

Plus the stdlib tag (`STDLIB_VERSION`) and the Cabal flag that selects the Agda
version in the language server (`ALS_AGDA_FLAG`).

## 1. Find the upstream revisions

- ALS: check `agda-web/agda-language-server` for a commit that supports the
  new Agda version. The Cabal file declares one flag per supported Agda
  (`Agda-2-6-4`, `Agda-2-7-0`, `Agda-2-8-0`, …); pick the matching
  `ALS_AGDA_FLAG`. Note its commit SHA as `ALS_REVISION`.
- Agda: check `agda-web/agda` for the revision the ALS expects (its build
  instructions or CI usually name it). Note it as `AGDA_REVISION`.
- ghc-wasm-meta: Agda's WASM build is pinned to a GHC flavour. If the new
  Agda needs a newer GHC, bump `GHC_WASM_META_FLAVOUR` and pick a
  `ghc-wasm-meta` revision that ships it as `GHC_WASM_META_REVISION`.
  Otherwise keep both.

## 2. Set the version on `main`

All work happens on `main`, the repository's only branch. Check it out:

```sh
git checkout main
```

## 3. Edit `config/version.env`

Set `AGDA_VERSION`, `ALS_WASM_NAME`, `STDLIB_VERSION`, `ALS_AGDA_FLAG`, and
the four revisions. Keep the `ALS_WASM_NAME` convention of the existing
releases (`als-2.8ext`) so downstream apps keep a predictable name.

## 4. Check the entropy patch

`patches/entropy-wasm-simple.patch` makes `entropy-$ENTROPY_VERSION` build
under WASI by replacing its custom `Setup.hs` (which probes the host CPU) with
the ordinary portable build. If the new toolchain or sources change the
`entropy` package, the patch may need a matching bump to `ENTROPY_VERSION`
and regeneration of the diff. The build refuses to proceed if the patch does
not apply cleanly, so this cannot be missed silently.

Agda itself ships stock: the build aborts if the pinned Agda tree has tracked
modifications.

## 5. Build

Either run the Build WASM and Build artifacts workflows from the Actions tab
("Run workflow"; Build artifacts asks for a tag), or build locally with the
pinned toolchain. On `main`, pushing a change to a WASM build input
(`config/version.env`, `scripts/build-als-wasm.sh`, the cross-compile patch,
or the workflow file itself) triggers the WASM compile automatically.
Documentation changes and the cheaper data/stdlib archive scripts leave the
cache alone, so unrelated commits skip the hour-long rebuild.

To build locally with the pinned toolchain:

```sh
git clone --filter=blob:none https://gitlab.haskell.org/ghc/ghc-wasm-meta.git
git -C ghc-wasm-meta fetch --depth=1 origin "$GHC_WASM_META_REVISION"
git -C ghc-wasm-meta checkout --detach FETCH_HEAD
FLAVOUR=$GHC_WASM_META_FLAVOUR PREFIX=$HOME/.ghc-wasm ./ghc-wasm-meta/setup.sh
source $HOME/.ghc-wasm/env

./scripts/build-als-wasm.sh
./scripts/fetch-stdlib-archive.sh
./scripts/build-data-archive.sh
./scripts/build-stdlib-interfaces.sh
node scripts/compute-manifest.mjs
```

Host requirements: `git curl tar gzip zip unzip xz autoreconf alex happy
wasm-opt` plus the toolchain above.

The local path exists so maintainers can reproduce and debug a CI build.

## 6. Verify

```sh
node scripts/verify-artifacts.mjs
wasmtime run als-<ver>.wasm --version   # must name the expected Agda version
```

`verify-artifacts.mjs` checks every artifact against `dist-manifest.json`,
confirms the gzip copy inflates to the shipped wasm, and checks the interface
archive's `.agdai` count. The version banner confirms the binary is the one
you meant to ship.

Reproducibility caveat: the same pinned sources produce the same binary
modulo the toolchain. A different `wasm-opt` or WASI SDK can change the hash
without changing behaviour, so a build made on another machine may hash
differently; the manifest records what this build produced.

## 7. Release

Commit the configuration change to `main` (artifacts are gitignored and never
committed):

```sh
git add config/version.env
git commit -m "Add Agda <ver> configuration"
git push origin main
```

Then tag `main` to trigger a release (`v<agda>-als-<sha>`):

```sh
git tag v2.9.0-als-<short-sha>
git push origin v2.9.0-als-<short-sha>
```

The tag runs Build artifacts, which restores the cached wasm for the pinned
inputs (compiling it only if the cache is cold), builds the data and interface
archives, verifies everything against `dist-manifest.json`, and publishes the
release with the wasm, its gzip copy, both archives, the interface archive,
and the manifest. The released files are exactly the ones verified in the run.

Pushing `main` with a changed `config/version.env` starts Build WASM, which
fills the cache under the new key; a tag cut afterwards restores it. The
cache is scoped to the default branch so any tag can read it, but it expires
if untouched for long enough, in which case the tag falls back to compiling
the wasm itself (an hour-long job).

## Interfaces

`build-data-archive.sh` runs `--setup` with a native Agda of the exact
version (the official release binary by default) and then type-checks every
primitive module to produce the `.agdai` interfaces that ship inside
`agda-data.zip`. Interfaces record option and version hashes, so only an
Agda of the matching version can produce usable ones.

The native binary is used because the WASM artifact is a language server:
producing interfaces from it would require an LSP client plus a WASI host
that supports nonblocking stdin and the browser's drive layer, and stock
`wasmtime`/`wasmer` provide neither. To keep the two in lockstep, the script
diffs the primitive sources it produces against the pinned `agda-web/agda`
checkout (when present) and aborts on any difference. Since Agda ships
unpatched, the official binary and the pinned revision compile the same
sources; should they ever diverge, the check fails loudly. In that case
supply `AGDA_BINARY` pointing at a native build of the pinned revision (for
example via `cabal install`) to proceed. `AGDA_BINARY` also covers platforms
without an official Agda binary.

`build-stdlib-interfaces.sh` uses the same native binary to type-check every
module under the standard library's `src/` and publishes the resulting
interfaces as one file per module under `interfaces/<agdaVersion>/src/`, zipped
into `interfaces-<agdaVersion>.zip` (the published asset; `NO_ZIP=1` skips the
archive). A client downloads the archive at build time, extracts it into its own
static files, and fetches individual files lazily while Agda runs, so each
visitor downloads only the interfaces their checks ask for. The script is
restartable: it recompiles from scratch each run, and `JOBS` controls how many
modules are checked in parallel.

## Updating the machinery

For changes other than version bumps, such as documentation, workflows, or
tooling, commit the change to `main`. The next tagged build picks up the new
machinery; artifacts are never committed.
