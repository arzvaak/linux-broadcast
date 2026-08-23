#!/usr/bin/env bash
set -euo pipefail

: "${AFX_SDK_ROOT:?Set AFX_SDK_ROOT to the extracted NVIDIA AFX SDK}"

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(node -p "require('$project_root/ui/src-tauri/tauri.conf.json').version")"
release_dir="$project_root/build/releases/$version/portable"
work_dir="$(mktemp -d "$project_root/build/portable.XXXXXX")"
trap 'cmake -E remove_directory "$work_dir"' EXIT

cmake -S "$project_root/native" -B "$project_root/build/native-cmake" \
  -DAFX_SDK_ROOT="$AFX_SDK_ROOT" -DBUILD_TESTING=ON
cmake --build "$project_root/build/native-cmake" --parallel
ctest --test-dir "$project_root/build/native-cmake" --output-on-failure
npm ci --prefix "$project_root/ui"
cargo test --manifest-path "$project_root/ui/src-tauri/Cargo.toml" --locked
npm run tauri --prefix "$project_root/ui" -- build --no-bundle

cmake -E remove_directory "$release_dir"
install -d "$release_dir"
source_date_epoch="$(git -C "$project_root" log -1 --format=%ct)"
limit=$((2 * 1024 * 1024 * 1024))

for specification in "rtx20 sm_75" "rtx30 sm_86" "rtx40 sm_89" "rtx50 sm_120"; do
  read -r series architecture <<< "$specification"
  bundle_name="linux-broadcast-$version-$series-x86_64"
  bundle_root="$work_dir/$bundle_name"
  archive="$release_dir/$bundle_name.tar"

  install -d "$bundle_root"
  AFX_SDK_ROOT="$AFX_SDK_ROOT" LINUX_BROADCAST_MODEL_ARCHES="$architecture" \
    "$project_root/scripts/stage-nvidia-runtime.sh" "$bundle_root/nvidia"
  install -m 0755 "$project_root/ui/src-tauri/target/release/linux-broadcast" \
    "$bundle_root/linux-broadcast-app"
  install -m 0755 "$project_root/build/native-cmake/liblinux_broadcast_afx_ladspa.so" \
    "$bundle_root/liblinux_broadcast_afx_ladspa.so"
  install -m 0755 "$project_root/packaging/portable/linux-broadcast" \
    "$bundle_root/linux-broadcast"
  install -m 0644 "$project_root/packaging/portable/README.txt" "$bundle_root/README.txt"
  install -m 0644 "$project_root/LICENSE" "$bundle_root/LICENSE"

  tar --sort=name --mtime="@$source_date_epoch" --owner=0 --group=0 --numeric-owner \
    -C "$work_dir" -cf "$archive" "$bundle_name"

  size="$(stat -c %s "$archive")"
  if (( size >= limit )); then
    printf 'Portable release exceeds the 2 GiB asset limit: %s\n' "$archive" >&2
    exit 3
  fi
  [[ "$(tar -tf "$archive" | grep -c '\.trtpkg$')" -eq 1 ]]
  if tar -tf "$archive" | grep -q 'libcudnn'; then
    printf 'cuDNN library found in portable release: %s\n' "$archive" >&2
    exit 3
  fi
  cmake -E remove_directory "$bundle_root"
done

(
  cd "$release_dir"
  sha256sum ./*.tar > SHA256SUMS
)
printf 'Portable releases written to %s\n' "$release_dir"
