# agda-als-dist

WebAssembly distributions of the **Agda Language Server** (ALS) together with
the runtime data a browser-based Agda client needs: Agda's primitive library,
a matching standard-library bundle, and gzip transport copies. Everything is
built from unmodified upstream sources, and every artifact is pinned and
checksummed.

It is designed for any browser or WASI project that wants to run Agda without a
server — playgrounds, notebooks, editor integrations, teaching tools.

## Why this exists

Agda's would-be WebAssembly home, [`agda-web/agda-wasm-dist`](https://github.com/agda-web/agda-wasm-dist),
distributes only the **plain `agda` executable**. It does not ship the language
server, the gzip transport copies, the primitive data archive, the standard
library bundle, or a machine-readable manifest. Editors and LSP clients want
the language server, and shipping those extra pieces is what makes a
"first visit, start typing" experience possible.

This repository fills that gap. It does **not** replace `agda-wasm-dist`; the
two are complementary. See [`NOTICE.md`](NOTICE.md) for provenance.

## Branches: one per Agda release

Distribution follows the same branch-per-version convention as
`agda-wasm-dist`:

| Branch | Agda | ALS file | stdlib | Status |
| --- | --- | --- | --- | --- |
| `agda-2.8.0` | 2.8.0 | `als-2.8ext.wasm` | 2.3 | available |
| `agda-2.7.0.1` | 2.7.0.1 | `als-2.7ext.wasm` | 2.2 | planned |
| `agda-2.6.4.3` | 2.6.4.3 | `als-2.6.wasm` | 2.1 | planned |

`main` carries only the shared build machinery and documentation. Each
`agda-<version>` branch is self-contained: it pins its upstream revisions in
`config/version.env` and commits the artifacts it produced.

Consumers that support several Agda versions use one submodule (or one fetch)
per version branch.

## What a version branch contains

| File | Purpose |
| --- | --- |
| `als-<ver>.wasm` | The optimized (`cabal -O2` + `wasm-opt -Oz`) ALS for WASI |
| `als-<ver>.wasm.gz` | Gzip transport copy for `DecompressionStream` clients |
| `agda-data.zip` | Agda primitives (`lib/prim/...`), sources **and** interfaces |
| `agda-stdlib-<ver>.zip` | Matching standard-library sources |
| `dist-manifest.json` | Versions, pinned commits, byte lengths, SHA-256 hashes |

The standard-library archive is source-only so that clients which never import
it do not pay for it. The primitive archive, by contrast, ships precomputed
`.agdai` interfaces so no client ever recompiles the primitive library.

Agda 2.8 removed local interfaces and looks only in `_build/<version>/agda/`,
while this archive — matching the long-standing layout of browser Agda
bundles — stores interfaces beside their sources. A consumer therefore
relocates `lib/prim/**.agdai` to `lib/prim/_build/<agdaVersion>/agda/**.agdai`
after extraction (see plfa-playground's `src/lib/worker/drive.ts`).

## Consuming the artifacts

### As a git submodule

```sh
git submodule add -b agda-2.8.0 https://github.com/jespercockx/agda-als-dist.git vendor/agda-als-dist
git -C vendor/agda-als-dist checkout agda-2.8.0
```

Pin a release tag rather than the moving branch in committed projects.

### From a release

Tags are named `v<agda>-als-<sha>`, e.g. `v2.8.0-als-e6541f8`, and attach the
wasm, its gzip copy, both archives, and `dist-manifest.json`.

### Direct URLs

Because the artifacts are committed on the version branch, they are reachable
without any Git client:

```text
https://raw.githubusercontent.com/jespercockx/agda-als-dist/agda-2.8.0/als-2.8ext.wasm
https://raw.githubusercontent.com/jespercockx/agda-als-dist/agda-2.8.0/dist-manifest.json
```

## `dist-manifest.json`

The manifest is the contract for consumers. It replaces the byte lengths and
cache-bust strings that clients used to hardcode:

```json
{
  "schemaVersion": 1,
  "agdaVersion": "2.8.0",
  "stdlibVersion": "2.3",
  "pins": {
    "als": "e65419f89e3152c2922e948b3e4d24580172bc6a",
    "agda": "e2f8c69414fa115328280ecc4de1d2b7a23be7fa",
    "ghcWasmMeta": "c3f44696d29aaeadd755d69c51735954bfcd59db",
    "ghcWasmMetaFlavour": "9.10",
    "entropy": "0.4.1.11"
  },
  "wasm": {
    "path": "als-2.8ext.wasm",
    "compressedPath": "als-2.8ext.wasm.gz",
    "byteLength": 32998899,
    "sha256": "629af8a86004…",
    "compressedByteLength": 10186498,
    "compressedSha256": "…",
    "cacheBust": "629af8a86004"
  },
  "data": { "path": "agda-data.zip", "byteLength": 571535, "sha256": "…" },
  "stdlib": { "path": "agda-stdlib-2.3.zip", "byteLength": 1972500, "sha256": "…" }
}
```

`wasm.byteLength` is the uncompressed length, used to set `Content-Length` when
a client inflates the gzip copy itself. `wasm.cacheBust` is derived from the
artifact hash, so it changes whenever the binary does.

## Verification

Every push that touches an artifact is checked by
[`verify-artifacts.mjs`](scripts/verify-artifacts.mjs): byte length and SHA-256
of each file against `dist-manifest.json`, plus a check that the gzip copy
decompresses to exactly the committed wasm. Run it locally with:

```sh
node scripts/verify-artifacts.mjs
```

The build workflow additionally runs the produced wasm under `wasmtime` and
asserts it reports its version:

```
$ wasmtime run als-2.8ext.wasm --version
Agda v2.8.0 Language Server v6 (WebAssembly build RAW)
```

## Building

See [`UPDATING.md`](UPDATING.md) for the full runbook. In short, on an
`agda-<version>` branch:

```sh
# with the pinned ghc-wasm-meta toolchain on PATH
./scripts/build-als-wasm.sh        # -> als-<ver>.wasm (+ .gz)
./scripts/fetch-stdlib-archive.sh  # -> agda-stdlib-<ver>.zip
./scripts/build-data-archive.sh    # -> agda-data.zip
node scripts/compute-manifest.mjs  # -> dist-manifest.json
node scripts/verify-artifacts.mjs
```

CI runs exactly these steps; the local path exists so maintainers can reproduce
and debug a build.

`build-data-archive.sh` needs a native Agda of the exact version and downloads
the official release binary automatically (`AGDA_BINARY` overrides this, e.g.
for a locally built build of the pinned revision, or on platforms without an
official binary).

Why not let the WASM build generate its own primitive interfaces? The ALS is a
language server, not a command-line type checker: producing interfaces from it
means driving the LSP protocol, and it additionally requires a WASI host that
can switch stdin to nonblocking and provide the in-memory drive layer the
browser uses. Stock `wasmtime` and `wasmer` reject the nonblocking-stdin call
and stall during document open, so interface generation is done with the native
binary instead. Because the official Agda 2.8.0 release and the pinned
`agda-web/agda` revision are byte-identical, this produces interfaces the WASM
build accepts; `build-data-archive.sh` diffs the two source trees and aborts if
they ever diverge.

## License

Tooling and docs are MIT (see [`LICENSE`](LICENSE)). The artifacts are built
from Agda, the Agda Language Server, and agda-stdlib, each under its own
license; see [`NOTICE.md`](NOTICE.md).
