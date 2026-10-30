#!/usr/bin/env bash
#
# Build the Agda Language Server (ALS) for WASI from pinned upstream sources.
#
# This is a parameterized version of the build that used to live in
# plfa-playground's compiler/ directory. Everything version-specific comes from
# config/version.env so the same script works for every Agda version.
#
# Requirements (see README.md / UPDATING.md):
#   - the pinned ghc-wasm-meta toolchain (wasm32-wasi-cabal, wasm32-wasi-ghc)
#   - wasm-opt (binaryen)
#   - git curl tar gzip autoreconf alex happy
#
# Environment overrides:
#   AGDA_WASM_WORK_DIR  checkout/build directory (default .compiler-work)
#   AGDA_WASM_OUTPUT    output .wasm path (default <repo>/<ALS_WASM_NAME>.wasm)
#   WASM_CABAL          wasm32-wasi-cabal executable
#   WASM_OPT            wasm-opt executable

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../config/version.env
source "$repo_root/config/version.env"

work_dir=${AGDA_WASM_WORK_DIR:-"$repo_root/.compiler-work"}
source_dir="$work_dir/agda-language-server"
output_path=${AGDA_WASM_OUTPUT:-"$repo_root/${ALS_WASM_NAME}.wasm"}

: "${ALS_REVISION:?}" "${AGDA_REVISION:?}" "${ENTROPY_VERSION:?}" "${ALS_AGDA_FLAG:?}"

echo "Building ALS for Agda ${AGDA_VERSION} (${ALS_WASM_NAME})"
echo "  ALS revision: ${ALS_REVISION}"
echo "  Agda revision: ${AGDA_REVISION}"
echo "  output: ${output_path}"

wasm_cabal=${WASM_CABAL:-$(command -v wasm32-wasi-cabal || true)}
wasm_opt=${WASM_OPT:-$(command -v wasm-opt || true)}

if [[ -z "$wasm_cabal" ]]; then
  echo "wasm32-wasi-cabal was not found. Install the pinned ghc-wasm-meta toolchain or set WASM_CABAL." >&2
  exit 1
fi

for program in git curl tar gzip autoreconf alex happy; do
  if ! command -v "$program" >/dev/null 2>&1; then
    echo "$program is required to build Agda for WASM." >&2
    exit 1
  fi
done

toolchain_root=$(cd "$(dirname "$wasm_cabal")/../.." && pwd)
wasm_ghc="$toolchain_root/wasm32-wasi-ghc/bin/wasm32-wasi-ghc"
if [[ ! -x "$wasm_ghc" ]]; then
  wasm_ghc=$(command -v wasm32-wasi-ghc || true)
fi
if [[ -z "$wasm_ghc" ]] || [[ $($wasm_ghc --numeric-version) != 9.10.* ]]; then
  echo "This build is pinned to the ghc-wasm-meta 9.10 toolchain." >&2
  echo "Install revision ${GHC_WASM_META_REVISION} with FLAVOUR=${GHC_WASM_META_FLAVOUR}." >&2
  exit 1
fi

mkdir -p "$work_dir" "$(dirname "$output_path")"

if [[ ! -d "$source_dir/.git" ]]; then
  git clone --filter=blob:none https://github.com/agda-web/agda-language-server.git "$source_dir"
fi

git -C "$source_dir" fetch --depth=1 origin "$ALS_REVISION"
git -C "$source_dir" checkout --detach FETCH_HEAD
git -C "$source_dir" submodule update --init --recursive --depth=1
git -C "$source_dir/wasm-submodules/agda" fetch --depth=1 origin "$AGDA_REVISION"
git -C "$source_dir/wasm-submodules/agda" checkout --detach FETCH_HEAD
git -C "$source_dir/wasm-submodules/agda" submodule update --init --recursive --depth=1
if ! git -C "$source_dir/wasm-submodules/agda" diff --quiet ||
  ! git -C "$source_dir/wasm-submodules/agda" diff --cached --quiet; then
  echo "The pinned Agda source contains local modifications; refusing to build a non-stock compiler." >&2
  exit 1
fi

entropy_dir="$source_dir/wasm-submodules/entropy"
git -C "$source_dir" restore --source=HEAD --worktree -- cabal.project.wasm32
rm -rf "$entropy_dir"
mkdir -p "$entropy_dir"
curl -fL \
  "https://hackage.haskell.org/package/entropy-$ENTROPY_VERSION/entropy-$ENTROPY_VERSION.tar.gz" |
  tar -xz -C "$entropy_dir" --strip-components=1

entropy_patch="$repo_root/patches/entropy-wasm-simple.patch"
if git -C "$source_dir" apply --check "$entropy_patch"; then
  git -C "$source_dir" apply "$entropy_patch"
elif ! git -C "$source_dir" apply --reverse --check "$entropy_patch"; then
  echo "The WASM entropy patch no longer applies to the pinned sources." >&2
  exit 1
fi

(
  cd "$source_dir/wasm-submodules/network"
  autoreconf -i
)

cp "$source_dir/cabal.project.wasm32" "$source_dir/cabal.project"

(
  cd "$source_dir"
  "$wasm_cabal" update
  # Cabal otherwise defaults libraries/executables to -O1. -O2 costs build
  # time but improves the stock compiler's hot deserialisation/typechecking
  # path; this changes build flags only, never Agda source.
  "$wasm_cabal" configure --flag="$ALS_AGDA_FLAG" --enable-optimization=2
  "$wasm_cabal" build lib:agda
  "$wasm_cabal" build --dependencies-only
  "$wasm_cabal" build exe:als

  unoptimized_path=$("$wasm_cabal" list-bin exe:als)
  if [[ -n "$wasm_opt" ]]; then
    "$wasm_opt" "$unoptimized_path" -Oz -o "$output_path"
  else
    cp "$unoptimized_path" "$output_path"
    echo "wasm-opt was not found; copied the unoptimized compiler." >&2
  fi
)

gzip -9 --keep --force "$output_path"
sha256sum "$output_path" "$output_path.gz"
