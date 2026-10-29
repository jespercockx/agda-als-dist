#!/usr/bin/env bash
#
# Fetch the matching agda-stdlib release and repack it as
# agda-stdlib-<STDLIB_VERSION>.zip with a stable top-level directory.
#
# The archive is source-only; Agda interfaces are generated separately (see
# README.md, "Interfaces") so that consumers who never touch the standard
# library do not pay for them.
#
# Works on any branch: STDLIB_VERSION comes from config/version.env.

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../config/version.env
source "$repo_root/config/version.env"

version="${STDLIB_VERSION:?STDLIB_VERSION must be set in config/version.env}"
tag="v${version}"
dir_name="agda-stdlib-${version}"
out="$repo_root/${dir_name}.zip"
url="https://github.com/agda/agda-stdlib/archive/refs/tags/${tag}.tar.gz"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "Fetching ${url}"
curl -fL --retry 5 "$url" -o "$tmp/stdlib.tar.gz"
tar -xzf "$tmp/stdlib.tar.gz" -C "$tmp"

if [[ ! -d "$tmp/$dir_name" ]]; then
  echo "Expected directory '$dir_name' inside the ${tag} tarball; got:" >&2
  ls -1 "$tmp" >&2
  exit 1
fi

rm -f "$out"
# -X drops extra attributes (uid/gid/extra fields) so the archive is portable
# and reproducible across machines.
( cd "$tmp" && zip -r -X -q -9 "$out" "$dir_name" )

echo "Wrote $out"
sha256sum "$out"
