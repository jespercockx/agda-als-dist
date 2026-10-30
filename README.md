# agda-als-dist

WebAssembly distributions of the **Agda Language Server** (ALS) together with
the runtime data a browser-based Agda client needs: Agda's primitive library,
a matching standard-library bundle, precompiled standard-library interfaces, and
gzip transport copies. Everything is built from unmodified upstream sources, and
every artifact is pinned and checksummed.

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

## Releases: one per Agda version

Each supported Agda release gets one GitHub **Release**, tagged
`v<agda>-als-<sha>` (for example `v2.8.0-als-e6541f8`). The release attaches the
built artifacts described below as **release assets**. That is where they live:
none of them are committed to a branch, so download them from the release page
(or its `https://github.com/jespercockx/agda-als-dist/releases/download/<tag>/<asset>`
URLs), not from a branch checkout.

| Release | Agda | ALS file | stdlib |
| --- | --- | --- | --- |
| `v2.8.0-als-e6541f8` | 2.8.0 | `als-2.8ext.wasm` | 2.3 |

`main` carries the build machinery, the documentation, and the version pins in
`config/version.env`. A release is built from the tagged commit on `main`; there
is no per-version branch. To cut a release, set `config/version.env` on `main`
and push a `v<agda>-als-<sha>` tag (see [`UPDATING.md`](UPDATING.md)). Existing
releases stay pinned to their own tags, so the shared, version-parameterized
machinery can move on without affecting them.

Agda 2.8.0 and later are supported: earlier releases predate the `--setup`
primitive installer that the WASM language server uses, and the
`_build/<version>/agda/` interface layout relied on below.

Consumers that build against several Agda versions pin one release per version.

## What a release contains

| Asset | Purpose |
| --- | --- |
| `als-<ver>.wasm` | The optimized (`cabal -O2` + `wasm-opt -Oz`) ALS for WASI |
| `als-<ver>.wasm.gz` | Gzip transport copy for `DecompressionStream` clients |
| `agda-data.zip` | Agda primitives: `lib/prim/...` sources plus interfaces under `lib/prim/_build/<agdaVersion>/agda/` |
| `agda-stdlib-<ver>.zip` | Matching standard-library sources |
| `interfaces-<agdaVersion>.zip` | Precompiled standard-library interfaces, `src/**/*.agdai`, one file per module |
| `dist-manifest.json` | Versions, pinned commits, byte lengths, SHA-256 hashes |

The standard-library *source* archive is small so that clients which never
import the library do not pay for it. The primitive archive, by contrast, ships
precomputed `.agdai` interfaces so no client ever recompiles the primitive
library.

The standard-library interface archive is the standard-library equivalent,
split into one file per module so a client can fetch exactly the interfaces a
check asks for instead of the whole library (see the template's `interfaces`
setting). Its root is `src/`, mirroring the layout Agda writes under
`_build/<agdaVersion>/agda/src/`, so a consumer maps a module the drive asks for
to `<baseUrl>/src/<Module>.agdai`. It is downloaded once at build time and
served same-origin; see the note on CORS below.

Agda 2.8 and later look for interfaces only under `_build/<agdaVersion>/agda/`
(local interfaces beside sources were removed), so the primitive archive puts
them exactly where Agda will look:

```text
lib/prim/_build/2.8.0/agda/Agda/Builtin/Nat.agdai
```

A consumer extracts the archive into its Agda data directory as-is; there is no
relocation step. `dist-manifest.json` also records this location as
`data.interfaceDir`.

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

The template's `scripts/sync-runtime.mjs` does exactly this, checking every
file against `dist-manifest.json` and caching the downloads so a warm checkout
needs no network. Pin the release tag (and, if you want the tag itself
authenticated, the manifest's SHA-256) in committed projects.

### Release assets are not CORS-readable

GitHub redirects release downloads to `release-assets.githubusercontent.com`,
whose responses carry no `access-control-allow-origin`. A page that is
cross-origin isolated with COOP/COEP therefore **cannot** fetch an individual
release asset from the browser. Release assets are a build-time and human
channel only: download the interface archive while building the site, extract it
into the site's static files, and serve it same-origin. A runtime
per-file fetch has to target a CORS host (GitHub Pages, `raw.githubusercontent.com`,
jsDelivr), never a release asset.

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

`wasm.byteLength` is the uncompressed length, used to set `Content-Length` when
a client inflates the gzip copy itself. `wasm.cacheBust` is derived from the
artifact hash, so it changes whenever the binary does. `interfaces` describes
the standard-library interface archive and is absent when the archive was not
built.

## Verification

Two workflows check every artifact, byte length and SHA-256 against
`dist-manifest.json`, plus that the gzip copy decompresses to exactly the wasm
and that the interface archive holds the recorded number of `.agdai` files:

- `build-artifacts.yml` verifies what it just built, before uploading it.
- `release.yml` re-verifies the uploaded artifact after downloading it, before
  attaching it to the release.

The build workflow additionally runs the produced wasm under `wasmtime` and
asserts it reports its version:

```
$ wasmtime run als-2.8ext.wasm --version
Agda v2.8.0 Language Server v6 (WebAssembly build RAW)
```

`verify-artifacts.mjs` expects the artifacts and manifest in the repository
root; run it locally after a local build with:

```sh
node scripts/verify-artifacts.mjs
```

## Building

See [`UPDATING.md`](UPDATING.md) for the full runbook. In short, from a checkout
of `main`:

```sh
# with the pinned ghc-wasm-meta toolchain on PATH
./scripts/build-als-wasm.sh            # -> als-<ver>.wasm (+ .gz)
./scripts/fetch-stdlib-archive.sh      # -> agda-stdlib-<ver>.zip
./scripts/build-data-archive.sh        # -> agda-data.zip
./scripts/build-stdlib-interfaces.sh   # -> interfaces/<agdaVersion>/ + interfaces-<agdaVersion>.zip
node scripts/compute-manifest.mjs      # -> dist-manifest.json
node scripts/verify-artifacts.mjs
```

CI runs these steps split across two workflows. `build-wasm.yml` owns the
expensive part (it compiles Agda) and runs only when a *WASM* input changes
(`config/version.env`, `scripts/build-als-wasm.sh`, `patches/**`, or the
workflow itself); it uploads the wasm as the `als-wasm` artifact.
`build-artifacts.yml` builds the cheap artifacts from a version tag and reuses
that wasm artifact when its `wasm-info.json` matches the tag's
`config/version.env`, falling back to compiling it. `release.yml` then attaches
the verified files to the release. The local path above exists so maintainers
can reproduce and debug a build.

`build-data-archive.sh` and `build-stdlib-interfaces.sh` need a native Agda of
the exact version and download the official release binary automatically
(`AGDA_BINARY` overrides this, e.g. for a locally built build of the pinned
revision, or on platforms without an official binary).

Why not let the WASM build generate its own interfaces? The ALS is a language
server, not a command-line type checker: producing interfaces from it means
driving the LSP protocol, and it additionally requires a WASI host that can
switch stdin to nonblocking and provide the in-memory drive layer the browser
uses. Stock `wasmtime` and `wasmer` reject the nonblocking-stdin call and stall
during document open, so interface generation is done with the native binary
instead. Because the official Agda 2.8.0 release and the pinned `agda-web/agda`
revision are byte-identical, this produces interfaces the WASM build accepts;
when the pinned `agda-web/agda` checkout is present, `build-data-archive.sh`
diffs the two source trees and aborts if they ever diverge.

## License

Tooling and docs are MIT (see [`LICENSE`](LICENSE)). The artifacts are built
from Agda, the Agda Language Server, and agda-stdlib, each under its own
license; see [`NOTICE.md`](NOTICE.md).
