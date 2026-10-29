#!/usr/bin/env node
//
// Verify the committed artifacts on this branch against dist-manifest.json.
//
// Checks, for every artifact: presence, byte length, and SHA-256. Additionally
// re-checks that the gzip transport copy decompresses to the exact wasm that is
// committed, so a stale or mismatched `.gz` cannot slip through.
//
// Usage: node scripts/verify-artifacts.mjs

import { createHash } from "node:crypto";
import { existsSync, readFileSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { gunzipSync } from "node:zlib";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifestPath = join(repoRoot, "dist-manifest.json");

// Artifacts live on the per-version branches (agda-<version>). The shared
// `main` branch and pull requests targeting it carry no manifest, so there is
// nothing to verify there.
if (!existsSync(manifestPath)) {
  console.log("No dist-manifest.json on this branch; nothing to verify.");
  process.exit(0);
}

const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));

const failures = [];

function sha256(buffer) {
  return createHash("sha256").update(buffer).digest("hex");
}

function check(label, relativePath, expectedBytes, expectedSha) {
  const absolute = join(repoRoot, relativePath);
  if (!existsSync(absolute)) {
    failures.push(`${label}: missing ${relativePath}`);
    return null;
  }
  const buffer = readFileSync(absolute);
  const bytes = statSync(absolute).size;
  if (bytes !== expectedBytes) {
    failures.push(`${label}: ${relativePath} is ${bytes} bytes, manifest says ${expectedBytes}`);
  }
  const sha = sha256(buffer);
  if (sha !== expectedSha) {
    failures.push(`${label}: ${relativePath} sha256 ${sha}, manifest says ${expectedSha}`);
  }
  if (bytes === expectedBytes && sha === expectedSha) {
    console.log(`ok  ${label} (${relativePath}, ${bytes} bytes)`);
  }
  return buffer;
}

const wasmBuffer = check("wasm", manifest.wasm.path, manifest.wasm.byteLength, manifest.wasm.sha256);
check(
  "wasm.gz",
  manifest.wasm.compressedPath,
  manifest.wasm.compressedByteLength,
  manifest.wasm.compressedSha256,
);
check("data", manifest.data.path, manifest.data.byteLength, manifest.data.sha256);
check("stdlib", manifest.stdlib.path, manifest.stdlib.byteLength, manifest.stdlib.sha256);

if (wasmBuffer) {
  const compressed = readFileSync(join(repoRoot, manifest.wasm.compressedPath));
  const inflated = gunzipSync(compressed);
  const sha = sha256(inflated);
  if (sha !== manifest.wasm.sha256) {
    failures.push(
      `wasm.gz: decompresses to sha256 ${sha}, expected the committed wasm ${manifest.wasm.sha256}`,
    );
  } else {
    console.log("ok  wasm.gz decompresses to the committed wasm");
  }
}

if (failures.length > 0) {
  console.error("\nVerification failed:");
  for (const failure of failures) console.error(`  - ${failure}`);
  process.exit(1);
}

console.log(`\nAll artifacts for Agda ${manifest.agdaVersion} verified.`);
