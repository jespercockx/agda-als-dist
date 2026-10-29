#!/usr/bin/env bash
#
# Generate agda-data.zip: Agda's primitive library (sources + interfaces),
# matching the layout today's browsers expect.
#
# Why a *native* Agda binary: interfaces (.agdai) record option/version hashes
# and can only be produced by an Agda of the exact version. The official Agda
# release binary for AGDA_VERSION is used for that. This is the same mechanism
# the consuming playground already uses to precompile standard-library and book
# interfaces (see plfa-playground's scripts/precompile-plfa.mjs), and it does
# not depend on any private repository.
#
# For versions whose Agda Language Server WASM build may have diverged from the
# official Agda release, set AGDA_BINARY to a native build of the pinned
# revision. When the pinned agda-web/agda checkout is present (it is after
# build-als-wasm.sh), the primitive sources produced here are diffed against it
# and the build aborts on any difference, so a mismatched archive cannot be
# published silently.
#
# Layout: entries are `lib/prim/...` (the sources) together with the interfaces
# Agda wrote under `lib/prim/_build/<agdaVersion>/agda/...`, which is exactly
# where Agda 2.8 and later look for them. Consumers extract the archive as-is;
# there is no relocation step.
#
# Environment overrides:
#   AGDA_BINARY   native Agda binary to use (default: official release download)
#   OUTPUT        output .zip path (default <repo>/agda-data.zip)

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../config/version.env
source "$repo_root/config/version.env"

agda_version="${AGDA_VERSION:?AGDA_VERSION must be set in config/version.env}"
work_dir="$repo_root/.compiler-work"
native_dir="$work_dir/agda-native-${agda_version}"
output=${OUTPUT:-"$repo_root/agda-data.zip"}

agda_bin=${AGDA_BINARY:-}

if [[ -z "$agda_bin" ]]; then
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64) asset="Agda-v${agda_version}-linux.tar.xz" ;;
    Linux-aarch64)
      echo "No official aarch64 Linux binary yet; set AGDA_BINARY to a native Agda ${agda_version}." >&2
      exit 1
      ;;
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

echo "Running --setup in $sandbox"
Agda_datadir="$sandbox" "$agda_bin" --setup >/dev/null

prim_dir=$(find "$sandbox" -type d -path '*/lib/prim' | head -n1)
if [[ -z "$prim_dir" ]]; then
  echo "Could not locate lib/prim after --setup." >&2
  find "$sandbox" >&2
  exit 1
fi

# The official binary may lay data out under $Agda_datadir/<version>/.
pinned_prim="$work_dir/agda-language-server/wasm-submodules/agda/src/data/lib/prim"
if [[ -d "$pinned_prim" ]]; then
  echo "Checking primitive sources against the pinned agda-web/agda tree"
  if ! diff -r -q "$pinned_prim" "$prim_dir" >/dev/null; then
    echo "The primitive sources from Agda ${agda_version} differ from the pinned agda-web/agda revision." >&2
    echo "The WASM build may have diverged from the official release; set AGDA_BINARY to a native build" >&2
    echo "of the pinned revision instead of relying on the official binary." >&2
    diff -r -q "$pinned_prim" "$prim_dir" >&2 || true
    exit 1
  fi
fi

echo "Type-checking primitive modules to produce interfaces"
export Agda_datadir="$sandbox"
while IFS= read -r file; do
  ( cd "$prim_dir" && "$agda_bin" --warning=noUnsupportedIndexedMatch --no-libraries -i . "$file" >/dev/null )
done < <(cd "$prim_dir" && find Agda -name '*.agda' | sort)

build_dir="$prim_dir/_build"
if [[ ! -d "$build_dir" ]]; then
  echo "Agda produced no _build directory; expected primitive interfaces." >&2
  exit 1
fi

staging=$(mktemp -d)
trap 'rm -rf "$sandbox" "$staging"' EXIT

mkdir -p "$staging/lib/prim"
cp -a "$prim_dir"/. "$staging/lib/prim/"

# Keep the interfaces under _build/<agdaVersion>/agda/ (Agda's own layout) and
# drop anything else the build directory accumulated.
rm -rf "$staging/lib/prim/_build"
( cd "$prim_dir" && find _build -name '*.agdai' -print0 |
  while IFS= read -r -d '' iface; do
    dest="$staging/lib/prim/$iface"
    mkdir -p "$(dirname "$dest")"
    cp -a "$iface" "$dest"
  done )

count=$(cd "$staging" && find lib/prim/_build -name '*.agdai' | wc -l)
echo "Bundling ${count} primitive interfaces"

rm -f "$output"
( cd "$staging" && zip -r -X -q -9 "$output" lib )

echo "Wrote $output"
sha256sum "$output"
