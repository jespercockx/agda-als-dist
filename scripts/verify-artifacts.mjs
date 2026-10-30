#!/usr/bin/env node
//
// Verify a set of runtime artifacts against dist-manifest.json.
//
// Checks, for every artifact: presence, byte length, and SHA-256. Additionally
// re-checks that the gzip transport copy decompresses to the exact wasm, and
// that the standard-library interface archive (when the manifest lists one)
// still holds the recorded number of `.agdai` files.
//
// Usage: node scripts/verify-artifacts.mjs
//
// The artifacts and manifest are expected in the repository root (or wherever
// this is run from): the build-artifacts workflow produces them there, and the
// release workflow downloads the built artifact into the root before running
// this, so the same check guards both hand-offs.

import { createHash } from "node:crypto";
import { existsSync, readFileSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { gunzipSync } from "node:zlib";

import { countZipEntries } from "./lib/zip.mjs";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifestPath = join(repoRoot, "dist-manifest.json");

// The manifest is produced by the build, not committed, so a checkout without
// one has nothing to verify.
if (!existsSync(manifestPath)) {
  console.log("No dist-manifest.json here; nothing to verify.");
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

if (manifest.interfaces) {
  const { asset, count, byteLength, sha256: expected } = manifest.interfaces;
  const buffer = check("interfaces", asset, byteLength, expected);
  if (buffer) {
    const actualCount = countZipEntries(buffer, ".agdai");
    if (actualCount !== count) {
      failures.push(`interfaces: ${asset} holds ${actualCount} .agdai files, manifest says ${count}`);
    } else {
      console.log(`ok  interfaces (${actualCount} .agdai files)`);
    }
  }
}

if (wasmBuffer) {
  const compressed = readFileSync(join(repoRoot, manifest.wasm.compressedPath));
  const inflated = gunzipSync(compressed);
  const sha = sha256(inflated);
  if (sha !== manifest.wasm.sha256) {
    failures.push(
      `wasm.gz: decompresses to sha256 ${sha}, expected the shipped wasm ${manifest.wasm.sha256}`,
    );
  } else {
    console.log("ok  wasm.gz decompresses to the shipped wasm");
  }
}

if (failures.length > 0) {
  console.error("\nVerification failed:");
  for (const failure of failures) console.error(`  - ${failure}`);
  process.exit(1);
}

console.log(`\nAll artifacts for Agda ${manifest.agdaVersion} verified.`);
