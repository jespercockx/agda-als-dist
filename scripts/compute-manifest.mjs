#!/usr/bin/env node
//
// Compute dist-manifest.json for this branch from config/version.env and the
// artifact files sitting next to it.
//
// The manifest is the machine-readable contract consumed by downstream apps
// (see plfa-playground's scripts/sync-runtime.mjs): package versions, pinned
// upstream commits, byte lengths, and SHA-256 hashes of every artifact.
//
// Usage: node scripts/compute-manifest.mjs

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

for (const key of ["AGDA_VERSION", "ALS_WASM_NAME", "STDLIB_VERSION", "ALS_REVISION", "AGDA_REVISION"]) {
  if (!version[key]) throw new Error(`config/version.env is missing ${key}`);
}

function describe(relativePath) {
  const absolute = join(repoRoot, relativePath);
  if (!existsSync(absolute)) {
    throw new Error(`Missing artifact ${relativePath}; run the build scripts first.`);
  }
  const bytes = statSync(absolute).size;
  const sha256 = createHash("sha256").update(readFileSync(absolute)).digest("hex");
  return { path: relativePath, byteLength: bytes, sha256 };
}

const wasmPath = `${version.ALS_WASM_NAME}.wasm`;
const compressedPath = `${wasmPath}.gz`;
const dataPath = "agda-data.zip";
const stdlibPath = `agda-stdlib-${version.STDLIB_VERSION}.zip`;

const wasm = describe(wasmPath);
const compressed = describe(compressedPath);
const data = describe(dataPath);
const stdlib = describe(stdlibPath);

const manifest = {
  schemaVersion: 1,
  agdaVersion: version.AGDA_VERSION,
  stdlibVersion: version.STDLIB_VERSION,
  pins: {
    als: version.ALS_REVISION,
    agda: version.AGDA_REVISION,
    ghcWasmMeta: version.GHC_WASM_META_REVISION,
    ghcWasmMetaFlavour: version.GHC_WASM_META_FLAVOUR,
    entropy: version.ENTROPY_VERSION,
  },
  wasm: {
    path: wasm.path,
    compressedPath: compressed.path,
    byteLength: wasm.byteLength,
    sha256: wasm.sha256,
    compressedByteLength: compressed.byteLength,
    compressedSha256: compressed.sha256,
    // Content-derived cache-bust token; replaces the hand-maintained
    // `?cache=...` query the app used to hardcode.
    cacheBust: wasm.sha256.slice(0, 12),
  },
  data: {
    path: data.path,
    byteLength: data.byteLength,
    sha256: data.sha256,
    // Where the precompiled primitive interfaces live inside the archive
    // (Agda 2.8+ only looks under _build/<version>/agda/).
    interfaceDir: `lib/prim/_build/${version.AGDA_VERSION}/agda`,
  },
  stdlib: {
    path: stdlib.path,
    byteLength: stdlib.byteLength,
    sha256: stdlib.sha256,
  },
};

const manifestPath = join(repoRoot, "dist-manifest.json");
writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + "\n");
console.log(`Wrote ${manifestPath}`);
console.log(JSON.stringify(manifest, null, 2));
