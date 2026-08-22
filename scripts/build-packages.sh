#!/usr/bin/env bash
set -euo pipefail

: "${AFX_SDK_ROOT:?Set AFX_SDK_ROOT to the extracted NVIDIA AFX SDK}"

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
staging="$project_root/build/nvidia-runtime"
series="${1:-}"

case "$series" in
  rtx20) architecture=sm_75 ;;
  rtx30) architecture=sm_86 ;;
  rtx40) architecture=sm_89 ;;
  rtx50) architecture=sm_120 ;;
  *) printf 'Usage: %s rtx20|rtx30|rtx40|rtx50\n' "$0" >&2; exit 2 ;;
esac
export LINUX_BROADCAST_MODEL_ARCHES="$architecture"

cmake -S "$project_root/native" -B "$project_root/build/native-cmake" \
  -DAFX_SDK_ROOT="$AFX_SDK_ROOT" -DBUILD_TESTING=ON
cmake --build "$project_root/build/native-cmake" --parallel
ctest --test-dir "$project_root/build/native-cmake" --output-on-failure

if [[ -e "$staging" ]]; then
  cmake -E remove_directory "$staging"
fi
"$project_root/scripts/stage-nvidia-runtime.sh" "$staging"

npm ci --prefix "$project_root/ui"
cargo test --manifest-path "$project_root/ui/src-tauri/Cargo.toml" --locked
cmake -E remove_directory "$project_root/ui/src-tauri/target/release/bundle/rpm"
cmake -E remove_directory "$project_root/ui/src-tauri/target/release/bundle/deb"
npm run tauri --prefix "$project_root/ui" -- build \
  --config src-tauri/tauri.bundle.conf.json --bundles rpm,deb

version="$(node -p "require('$project_root/ui/src-tauri/tauri.conf.json').version")"
release_dir="$project_root/build/releases/$version/$series"
install -d "$release_dir"
mv "$project_root/ui/src-tauri/target/release/bundle/rpm/Linux Broadcast-$version-1.x86_64.rpm" \
  "$release_dir/linux-broadcast-$version-$series.x86_64.rpm"
mv "$project_root/ui/src-tauri/target/release/bundle/deb/Linux Broadcast_${version}_amd64.deb" \
  "$release_dir/linux-broadcast_${version}_${series}_amd64.deb"

(
  cd "$release_dir"
  sha256sum ./*.rpm ./*.deb > SHA256SUMS
)

limit=$((2 * 1024 * 1024 * 1024))
for artifact in "$release_dir"/*.rpm "$release_dir"/*.deb; do
  size="$(stat -c %s "$artifact")"
  if (( size >= limit )); then
    printf 'Release artifact exceeds the 2 GiB distribution limit: %s\n' "$artifact" >&2
    exit 3
  fi
done
printf 'Release packages written to %s\n' "$release_dir"
