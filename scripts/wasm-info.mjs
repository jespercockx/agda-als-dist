#!/usr/bin/env node
//
// Write wasm-info.json describing the ALS wasm sitting in the repository root:
// the Agda version, the pinned upstream revisions, and the artifact hash.
//
// build-wasm.yml uploads this file next to the wasm so build-artifacts.yml can
// tell whether an existing build matches the version branch it is releasing
// before reusing it. It is a build-time hand-off file, not a release asset.
//
// Usage: node scripts/wasm-info.mjs

import { createHash } from "node:crypto";
import { existsSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");

function parseEnv(text) {
  const out = {};
  for (const line of text.split("\n")) {
    const match = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/.exec(line);
    if (match) out[match[1]] = match[2];
  }
  return out;
}

const version = parseEnv(readFileSync(join(repoRoot, "config", "version.env"), "utf8"));
const wasmPath = `${version.ALS_WASM_NAME}.wasm`;
const absolute = join(repoRoot, wasmPath);
if (!existsSync(absolute)) {
  throw new Error(`Missing ${wasmPath}; build the WASM first.`);
}

const info = {
  agdaVersion: version.AGDA_VERSION,
  pins: {
    als: version.ALS_REVISION,
    agda: version.AGDA_REVISION,
    ghcWasmMeta: version.GHC_WASM_META_REVISION,
    ghcWasmMetaFlavour: version.GHC_WASM_META_FLAVOUR,
    entropy: version.ENTROPY_VERSION,
  },
  wasm: {
    path: wasmPath,
    byteLength: statSync(absolute).size,
    sha256: createHash("sha256").update(readFileSync(absolute)).digest("hex"),
  },
};

const outputPath = join(repoRoot, "wasm-info.json");
writeFileSync(outputPath, JSON.stringify(info, null, 2) + "\n");
console.log(`Wrote ${outputPath}`);
