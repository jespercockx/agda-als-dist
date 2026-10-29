# Third-party notices

This repository distributes **build outputs**, not the upstream sources. The
tooling in `scripts/` and `patches/` is MIT-licensed (see `LICENSE`). The
artifacts it produces come from the projects below and remain under their own
licenses.

## Agda Language Server

Source: [`agda-web/agda-language-server`](https://github.com/agda-web/agda-language-server),
pinned per branch in `config/version.env`. MIT licensed.

## Agda

Source: [`agda-web/agda`](https://github.com/agda-web/agda) (a WASM-oriented
mirror of [`agda/agda`](https://github.com/agda/agda)), pinned per branch in
`config/version.env`. Agda is distributed under the MIT license, with parts
under other compatible licenses; see the Agda repository's `LICENSE`.

The build applies a single, narrow cross-compilation patch to the third-party
`entropy` package (`patches/entropy-wasm-simple.patch`); it never patches Agda
itself, and the build aborts if the pinned Agda tree has local modifications.

## agda-stdlib

Source: [`agda/agda-stdlib`](https://github.com/agda/agda-stdlib), release tag
`v<STDLIB_VERSION>` per branch. MIT licensed.

## ghc-wasm-meta

Toolchain: [`ghc/ghc-wasm-meta`](https://gitlab.haskell.org/ghc/ghc-wasm-meta),
pinned per branch. Used to build, not redistributed here.

## Relationship to agda-web/agda-wasm-dist

This project is not a fork. It distributes a **different artifact** (the
language server plus browser runtime data). `agda-web/agda-wasm-dist` ships the
plain `agda` command-line executable and publishes it via container images and
Actions artifacts; the two projects are complementary.
