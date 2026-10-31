# agda-als-dist

WebAssembly distributions of the Agda Language Server (ALS) together with the
runtime data a browser-based Agda client needs: Agda's primitive library, a
matching standard-library bundle, precompiled standard-library interfaces, and
gzip transport copies.

It is aimed at browser and WASI projects that want to run Agda without a
server: playgrounds, notebooks, editor integrations, teaching tools.

## Why this exists

Agda's WebAssembly distribution,
[`agda-web/agda-wasm-dist`](https://github.com/agda-web/agda-wasm-dist),
distributes only a plain `agda` executable. Editors and LSP clients also want
the language server, the gzip transport copy, the primitive data archive, the
standard-library bundle, and a machine-readable manifest; shipping those extra
pieces is what makes a first-visit, start-typing experience possible. This
repository distributes that full set, complementing `agda-wasm-dist`. See
[`NOTICE.md`](NOTICE.md) for provenance.

## Releases

Each supported Agda release gets one GitHub Release, tagged
`v<agda>-als-<sha>` (for example `v2.8.0-als-e6541f8`). The built artifacts
described below are attached to the release as release assets. Download them
from the release page or its
`https://github.com/jespercockx/agda-als-dist/releases/download/<tag>/<asset>`
URLs; they are attached to the release only, so a branch checkout contains
just the build machinery.

| Release | Agda | ALS file | stdlib |
| --- | --- | --- | --- |
| [`v2.8.0-als-e6541f8`](https://github.com/jespercockx/agda-als-dist/releases/tag/v2.8.0-als-e6541f8) | 2.8.0 | `als-2.8ext.wasm` | 2.3 |

This repository carries the build machinery, the documentation, and the version
pins in `config/version.env`. Each releases is built from a tagged commit on
`main`. [`UPDATING.md`](UPDATING.md) contains instructions for adding a new
release.

Releases cover Agda 2.8.0 and later. Earlier Agda releases predate the
`--setup` primitive installer that the WASM language server uses, and the
`_build/<version>/agda/` interface layout described below.

## What a release contains

| Asset | Purpose |
| --- | --- |
| `als-<ver>.wasm` | The optimized (`cabal -O2` + `wasm-opt -Oz`) ALS for WASI |
| `als-<ver>.wasm.gz` | Gzip transport copy for `DecompressionStream` clients |
| `agda-data.zip` | Agda primitives: `lib/prim/...` sources plus interfaces under `lib/prim/_build/<agdaVersion>/agda/` |
| `agda-stdlib-<ver>.zip` | Matching standard-library sources |
| `interfaces-<agdaVersion>.zip` | Precompiled standard-library interfaces, `src/**/*.agdai`, one file per module |
| `dist-manifest.json` | Versions, pinned commits, byte lengths, SHA-256 hashes |

The `agda-data.zip` archive contains both sources and precompiled interface
files for Agda's minimal built-in library files.

The standard-library archive is split into a small source archive and a separate
archive with precomputed `.agdai` files for clients that wish to include them.
Agda 2.8 and later look for interfaces only under `_build/<agdaVersion>/agda/`
(local interfaces beside sources were removed), so the primitive archive puts
them exactly where Agda will look:

```text
lib/prim/_build/2.8.0/agda/Agda/Builtin/Nat.agdai
```

`dist-manifest.json` also records this location as `data.interfaceDir`.

## Consuming the artifacts

### From a release

Download the assets (and verify them against the manifest):

```sh
tag=v2.8.0-als-e6541f8
base=https://github.com/jespercockx/agda-als-dist/releases/download/$tag
curl -fLO "$base/dist-manifest.json"
curl -fLO "$base/als-2.8ext.wasm"
curl -fLO "$base/als-2.8ext.wasm.gz"
curl -fLO "$base/agda-data.zip"
curl -fLO "$base/agda-stdlib-2.3.zip"
curl -fLO "$base/interfaces-2.8.0.zip"
```

Extract the archives into your site's static files, and serve it same-origin.

GitHub redirects release downloads to `release-assets.githubusercontent.com`,
whose responses carry no `access-control-allow-origin`, so a page that is
cross-origin isolated with COOP/COEP cannot fetch an individual release asset
from the browser. For runtime per-file fetches, use a CORS host instead (GitHub
Pages, `raw.githubusercontent.com`, jsDelivr).

## Verification

Every artifact is recorded in `dist-manifest.json` with its byte length and
SHA-256; the manifest is also what confirms that the gzip copy decompresses to
exactly the wasm and that the interface archive holds the recorded number of
`.agdai` files.

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
  "data": {
    "path": "agda-data.zip",
    "byteLength": 574839,
    "sha256": "…",
    "interfaceDir": "lib/prim/_build/2.8.0/agda"
  },
  "stdlib": { "path": "agda-stdlib-2.3.zip", "byteLength": 1972500, "sha256": "…" },
  "interfaces": {
    "asset": "interfaces-2.8.0.zip",
    "byteLength": 165547885,
    "sha256": "…",
    "count": 1153,
    "root": "src"
  }
}
```

`wasm.byteLength` is the uncompressed length, used to set `Content-Length`
when a client inflates the gzip copy itself. `wasm.cacheBust` is derived from
the artifact hash, so it changes whenever the binary does. `interfaces`
describes the standard-library interface archive and is absent when the
archive was not built.

CI runs the same verification on the freshly built set right before
publishing a release, so the released files are exactly the ones it verified,
and additionally runs the produced wasm under `wasmtime`, asserting that it
reports its version:

```
$ wasmtime run als-2.8ext.wasm --version
Agda v2.8.0 Language Server v6 (WebAssembly build RAW)
```

## Building

Instructions for building the artifacts from source and cutting a new release
live in [`UPDATING.md`](UPDATING.md). In outline: the versions and pinned
revisions are set in `config/version.env`, the scripts in `scripts/` build
each artifact, and pushing a `v<agda>-als-<sha>` tag makes CI verify the set
and publish the release.

## License

Tooling and docs are MIT (see [`LICENSE`](LICENSE)). The artifacts are built
from Agda, the Agda Language Server, and agda-stdlib, each under its own
license; see [`NOTICE.md`](NOTICE.md).
