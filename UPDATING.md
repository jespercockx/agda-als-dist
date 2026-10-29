# Updating for a new Agda release

This runbook is intentionally mechanical: a new Agda release should require
editing one config file, running the build, and committing the result — no
tribal knowledge.

## The moving parts

A build brings together four pinned inputs, all recorded in
`config/version.env` on the version branch:

| Input | Where it is pinned | Notes |
| --- | --- | --- |
| Agda Language Server | `ALS_REVISION` | `agda-web/agda-language-server` |
| Agda | `AGDA_REVISION` | `agda-web/agda` (WASM mirror of `agda/agda`) |
| ghc-wasm-meta | `GHC_WASM_META_REVISION`, `GHC_WASM_META_FLAVOUR` | `ghc/ghc-wasm-meta` |
| entropy patch version | `ENTROPY_VERSION` | only the cross-compile patch is ours |

Plus the stdlib tag (`STDLIB_VERSION`) and the Cabal flag that selects the Agda
version in the language server (`ALS_AGDA_FLAG`).

## 1. Find the upstream revisions

- **ALS**: check `agda-web/agda-language-server` for a commit that supports the
  new Agda version. The Cabal file declares one flag per supported Agda
  (`Agda-2-6-4`, `Agda-2-7-0`, `Agda-2-8-0`, …); pick the matching
  `ALS_AGDA_FLAG`. Note its commit SHA as `ALS_REVISION`.
- **Agda**: check `agda-web/agda` for the revision the ALS expects (its build
  instructions or CI usually name it). Note it as `AGDA_REVISION`.
- **ghc-wasm-meta**: Agda's WASM build is pinned to a GHC flavour. If the new
  Agda needs a newer GHC, bump `GHC_WASM_META_FLAVOUR` and pick a
  `ghc-wasm-meta` revision that ships it as `GHC_WASM_META_REVISION`. Otherwise
  keep both.

## 2. Create the version branch

Branch from `main` so the shared machinery is inherited:

```sh
git checkout main
git checkout -b agda-2.9.0        # the new Agda release
```

## 3. Edit `config/version.env`

Set `AGDA_VERSION`, `ALS_WASM_NAME`, `STDLIB_VERSION`, `ALS_AGDA_FLAG`, and the
four revisions. Keep the `ALS_WASM_NAME` convention of the existing branches
(`als-2.8ext`) so downstream apps keep a predictable name.

## 4. Check the entropy patch

`patches/entropy-wasm-simple.patch` makes `entropy-$ENTROPY_VERSION` build
under WASI by replacing its custom `Setup.hs` (which probes the host CPU) with
the ordinary portable build. If the new toolchain or sources change the
`entropy` package, the patch may need a matching bump to `ENTROPY_VERSION` and
regeneration of the diff. The build refuses to proceed if the patch does not
apply cleanly, so this cannot be missed silently.

Do **not** patch Agda. The build aborts if the pinned Agda tree has tracked
modifications, which keeps the shipped compiler stock.

## 5. Build

Either run the **Build ALS WASM** workflow from the Actions tab ("Run
workflow"), or build locally with the pinned toolchain. On a version branch the
WASM compile also runs automatically when a WASM build input changes —
`config/version.env` (the pinned versions), `scripts/build-als-wasm.sh`, the
cross-compile patch, or the workflow file itself — but not for documentation,
verification, or the cheaper data/stdlib archive scripts, so unrelated commits
do not trigger hour-long rebuilds.

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
node scripts/compute-manifest.mjs
```

Host requirements: `git curl tar gzip zip autoreconf alex happy wasm-opt` plus
the toolchain above.

## 6. Verify

```sh
node scripts/verify-artifacts.mjs
wasmtime run als-<ver>.wasm --version   # must name the expected Agda version
```

`verify-artifacts.mjs` checks every file against `dist-manifest.json` and
confirms the gzip copy inflates to the committed wasm. The version banner
confirms the binary is the one you meant to ship.

Reproducibility caveat: the same pinned sources produce the same binary
*modulo the toolchain*. A different `wasm-opt` or WASI SDK can change the hash
without changing behaviour, so do not expect the hash to match a build made on
another machine — the manifest records what *this* build produced.

## 7. Commit and release

```sh
git add dist-manifest.json als-<ver>.wasm als-<ver>.wasm.gz agda-data.zip agda-stdlib-<ver>.zip
git commit -m "Add Agda <ver> artifacts"
git push origin agda-<ver>
```

Then tag to trigger a release (`v<agda>-als-<sha>`):

```sh
git tag v2.9.0-als-<short-sha>
git push origin v2.9.0-als-<short-sha>
```

The tag triggers `release.yml`, which re-verifies the committed artifacts
against `dist-manifest.json` and attaches the wasm, its gzip copy, both
archives, and the manifest to the release. It does not rebuild, so the released
files are exactly the ones committed on the branch.

## Interfaces

`build-data-archive.sh` runs `--setup` with a **native** Agda of the exact
version (the official release binary by default) and then type-checks every
primitive module to produce the `.agdai` interfaces that ship inside
`agda-data.zip`. Interfaces record option and version hashes, so only an Agda
of the matching version can produce usable ones.

This is deliberate rather than laziness: the WASM artifact is a language
server, and generating interfaces from it would mean implementing an LSP
client and running under a WASI host that supports nonblocking stdin and the
browser's drive layer. Stock `wasmtime`/`wasmer` do not, so the native binary
is used instead. To keep the two in lockstep, the script diffs the primitive
sources it produces against the pinned `agda-web/agda` checkout (present after
`build-als-wasm.sh`) and aborts on any difference. If a future WASM build
patches Agda, the check fails loudly — supply `AGDA_BINARY` pointing at a
native build of the pinned revision (for example via `cabal install`) to
proceed.

`AGDA_BINARY` also covers platforms without an official Agda binary.

## Updating a branch in place

For documentation, workflow, or tooling changes that are not version bumps,
commit the change to `main`, then merge `main` into each `agda-*` branch. Do
not recommit artifacts unless the binary actually changes.
