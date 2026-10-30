#!/usr/bin/env bash
#
# Build the standard-library interface archive:
#
#   interfaces-<agdaVersion>.zip, holding src/**/*.agdai
#
# The zip is the published release asset; the loose tree is left under
# interfaces/<agdaVersion>/ so compute-manifest.mjs can count it. The archive
# root is `src` (mirroring the layout Agda writes under
# _build/<agdaVersion>/agda/src/), so a consumer maps a module the drive asks
# for to <baseUrl>/src/<Module>.agdai.
#
# The playground can fetch individual files from this tree while Agda runs, so a
# consumer downloads only the interfaces a check actually needs (see the
# `interfaces` setting in the template's playground.config.json).
#
# Interfaces record Agda's option and version hashes and can only be produced by
# an Agda of the exact version, so a native Agda for AGDA_VERSION is used: the
# official release binary by default, or AGDA_BINARY. This mirrors the mechanism
# in build-data-archive.sh.
#
# Environment overrides:
#   AGDA_BINARY   native Agda binary (default: official release download)
#   OUT_DIR       output directory (default <repo>/interfaces/<agdaVersion>)
#   ZIP           output archive path (default <repo>/interfaces-<agdaVersion>.zip)
#   NO_ZIP        set to skip creating the archive (tree only)
#   JOBS          parallel Agda invocations (default: number of CPUs)
#   LIMIT         compile only the first N modules (for smoke-testing)

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../config/version.env
source "$repo_root/config/version.env"

agda_version="${AGDA_VERSION:?AGDA_VERSION must be set in config/version.env}"
stdlib_version="${STDLIB_VERSION:?STDLIB_VERSION must be set in config/version.env}"
stdlib_zip="$repo_root/agda-stdlib-${stdlib_version}.zip"
work_dir="$repo_root/.compiler-work"
out_dir=${OUT_DIR:-"$repo_root/interfaces/${agda_version}"}
zip_path=${ZIP:-"$repo_root/interfaces-${agda_version}.zip"}
no_zip=${NO_ZIP:-}
jobs=${JOBS:-$(nproc)}
limit=${LIMIT:-}

[ -f "$stdlib_zip" ] || {
  echo "Missing $stdlib_zip; run scripts/fetch-stdlib-archive.sh first." >&2
  exit 1
}

agda_bin=${AGDA_BINARY:-}
if [[ -z "$agda_bin" ]]; then
  native_dir="$work_dir/agda-native-${agda_version}"
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64) asset="Agda-v${agda_version}-linux.tar.xz" ;;
    *)
      echo "No official binary for $(uname -s)/$(uname -m); set AGDA_BINARY to a native Agda ${agda_version}." >&2
      exit 1
      ;;
  esac
  if [[ ! -x "$native_dir/agda" ]]; then
    mkdir -p "$native_dir"
    url="https://github.com/agda/agda/releases/download/v${agda_version}/${asset}"
    echo "Fetching ${url}"
    curl -fL --retry 5 "$url" -o "$native_dir/agda.tar.xz"
    tar -xJf "$native_dir/agda.tar.xz" -C "$native_dir"
    chmod +x "$native_dir/agda"
  fi
  agda_bin="$native_dir/agda"
fi

reported=$("$agda_bin" --version | head -n1)
if [[ "$reported" != "Agda version ${agda_version}"* ]]; then
  echo "Expected Agda version ${agda_version}, but '$agda_bin' reports: ${reported}" >&2
  exit 1
fi

sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
Agda_datadir="$sandbox" "$agda_bin" --setup >/dev/null
export Agda_datadir="$sandbox"

src_root="$work_dir/stdlib-${stdlib_version}"
rm -rf "$src_root"
mkdir -p "$src_root"
echo "Extracting $stdlib_zip"
unzip -q "$stdlib_zip" -d "$src_root"
stdlib_src="$src_root/agda-stdlib-${stdlib_version}/src"
[ -d "$stdlib_src" ] || {
  echo "Could not find $stdlib_src in the archive." >&2
  exit 1
}

log="$work_dir/stdlib-interfaces-${agda_version}.log"
: >"$log"
compile_one() {
  local file="$1"
  ( cd "$stdlib_src" && "$agda_bin" --no-libraries --warning=noUnsupportedIndexedMatch "$file" ) ||
    echo "SKIP $file" >>"$log"
}
export -f compile_one
export agda_bin stdlib_src log

modules=$(cd "$stdlib_src" && find . -name '*.agda' -printf '%P\n' | sort)
if [[ -n "$limit" ]]; then
  modules=$(printf '%s\n' "$modules" | head -n "$limit")
fi
total=$(printf '%s\n' "$modules" | wc -l)
echo "Compiling ${total} modules with ${jobs} parallel jobs"

printf '%s\n' "$modules" |
  xargs -P "$jobs" -I{} bash -c 'compile_one "$@"' _ {}

build_dir=$(find "$src_root" -type d -path "*/_build/${agda_version}/agda/src" | head -n1)
if [[ -z "$build_dir" || ! -d "$build_dir" ]]; then
  echo "Agda produced no interfaces under */_build/${agda_version}/agda/src" >&2
  exit 1
fi

rm -rf "$out_dir"
mkdir -p "$out_dir"
( cd "$build_dir" && find . -name '*.agdai' -print0 |
  while IFS= read -r -d '' iface; do
    dest="$out_dir/src/${iface#./}"
    mkdir -p "$(dirname "$dest")"
    cp -a "$iface" "$dest"
  done )

count=$(find "$out_dir" -name '*.agdai' | wc -l)
bytes=$(find "$out_dir" -name '*.agdai' -printf '%s\n' | awk '{total += $1} END {print total + 0}')
skipped=$(wc -l <"$log")
echo "Published ${count} interfaces (${bytes} bytes) to $out_dir"

if [[ -z "$no_zip" ]]; then
  rm -f "$zip_path"
  # -X strips extra file attributes so the archive is reproducible; the root is
  # `src`, exactly as Agda's own _build/<agdaVersion>/agda/ layout.
  ( cd "$out_dir" && zip -r -X -q -9 "$zip_path" src )
  echo "Wrote $zip_path ($(stat -c '%s' "$zip_path") bytes)"
fi

if [[ "$skipped" -gt 0 ]]; then
  echo "${skipped} module(s) skipped; see $log" >&2
fi
