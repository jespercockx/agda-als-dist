// Minimal read-only helpers for the ZIP archives this repository publishes.
//
// The command-line `zip`/`unzip` tools are used to *create* archives (see
// scripts/build-stdlib-interfaces.sh and the workflows), but reading a small
// amount of metadata back — how many entries an archive holds, and of which
// kind — is done here so the manifest and verification scripts run anywhere
// Node does, without shelling out.
//
// Only the parts of the format these archives use are implemented: the classic
// (non-ZIP64) end-of-central-directory record and central directory. The
// published archives are far below the 4 GiB / 65535-entry thresholds.

/** Locate the end-of-central-directory record, scanning back over any comment. */
function findEndOfCentralDirectory(buffer) {
  const earliest = Math.max(0, buffer.length - 22 - 0xffff);
  for (let offset = buffer.length - 22; offset >= earliest; offset--) {
    if (buffer.readUInt32LE(offset) === 0x06054b50) return offset;
  }
  throw new Error("not a ZIP archive: no end-of-central-directory record");
}

/**
 * Count central-directory entries whose name ends with `suffix`.
 * Directory entries (names ending in `/`) are ignored.
 */
export function countZipEntries(buffer, suffix = "") {
  const eocd = findEndOfCentralDirectory(buffer);
  const total = buffer.readUInt16LE(eocd + 10);
  let cursor = buffer.readUInt32LE(eocd + 16);
  let count = 0;
  for (let index = 0; index < total; index++) {
    if (buffer.readUInt32LE(cursor) !== 0x02014b50) {
      throw new Error("corrupt ZIP central directory");
    }
    const nameLength = buffer.readUInt16LE(cursor + 28);
    const extraLength = buffer.readUInt16LE(cursor + 30);
    const commentLength = buffer.readUInt16LE(cursor + 32);
    const name = buffer.toString("utf8", cursor + 46, cursor + 46 + nameLength);
    if (!name.endsWith("/") && name.endsWith(suffix)) count++;
    cursor += 46 + nameLength + extraLength + commentLength;
  }
  return count;
}
