#!/usr/bin/env bash
set -euo pipefail

: "${AFX_SDK_ROOT:?Set AFX_SDK_ROOT to the extracted NVIDIA AFX SDK}"

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
staging="$project_root/build/nvidia-runtime"
cargo_target_dir="${CARGO_TARGET_DIR:-$project_root/ui/src-tauri/target}"
series="${1:-}"

case "$series" in
  rtx20) architecture=sm_75 ;;
  rtx30) architecture=sm_86 ;;
  rtx40) architecture=sm_89 ;;
  rtx50) architecture=sm_120 ;;
  *) printf 'Usage: %s rtx20|rtx30|rtx40|rtx50\n' "$0" >&2; exit 2 ;;
esac
export LINUX_BROADCAST_MODEL_ARCHES="$architecture"

cmake -E remove_directory "$project_root/build/native-cmake"
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
npm run tauri --prefix "$project_root/ui" -- build --no-bundle

version="$(node -p "require('$project_root/ui/src-tauri/tauri.conf.json').version")"
release_dir="$project_root/build/releases/$version/$series"
install -d "$release_dir"
work_dir="$(mktemp -d "$project_root/build/packages.XXXXXX")"
trap 'cmake -E remove_directory "$work_dir"' EXIT
package_root="$work_dir/root"

install -d \
  "$package_root/usr/bin" \
  "$package_root/usr/lib/linux-broadcast" \
  "$package_root/usr/share/applications" \
  "$package_root/usr/share/icons/hicolor/128x128/apps" \
  "$package_root/usr/share/metainfo" \
  "$package_root/usr/share/licenses/linux-broadcast"
install -m 0755 "$cargo_target_dir/release/linux-broadcast" \
  "$package_root/usr/bin/linux-broadcast"
install -m 0755 "$project_root/build/native-cmake/liblinux_broadcast_afx_ladspa.so" \
  "$package_root/usr/lib/linux-broadcast/liblinux_broadcast_afx_ladspa.so"
cp -al "$staging" "$package_root/usr/lib/linux-broadcast/nvidia"
install -m 0644 "$project_root/packaging/linux-broadcast.desktop" \
  "$package_root/usr/share/applications/linux-broadcast.desktop"
install -m 0644 "$project_root/packaging/com.arzvak.linuxbroadcast.metainfo.xml" \
  "$package_root/usr/share/metainfo/com.arzvak.linuxbroadcast.metainfo.xml"
install -m 0644 "$project_root/ui/src-tauri/icons/128x128.png" \
  "$package_root/usr/share/icons/hicolor/128x128/apps/linux-broadcast.png"
install -m 0644 "$project_root/LICENSE" "$package_root/usr/share/licenses/linux-broadcast/LICENSE"

install -d "$package_root/DEBIAN"
installed_size="$(du -sk "$package_root/usr" | cut -f1)"
sed \
  -e "s/@VERSION@/$version/g" \
  -e "s/@INSTALLED_SIZE@/$installed_size/g" \
  "$project_root/packaging/deb/control.in" > "$package_root/DEBIAN/control"
dpkg-deb --build --root-owner-group -Znone "$package_root" \
  "$release_dir/linux-broadcast_${version}_${series}_amd64.deb"
cmake -E remove_directory "$package_root/DEBIAN"

rpm_top="$work_dir/rpmbuild"
install -d "$rpm_top/BUILD" "$rpm_top/BUILDROOT" "$rpm_top/RPMS" \
  "$rpm_top/SOURCES" "$rpm_top/SPECS" "$rpm_top/SRPMS"
sed \
  -e "s/@VERSION@/$version/g" \
  -e "s|@PACKAGE_ROOT@|$package_root|g" \
  "$project_root/packaging/rpm/linux-broadcast.spec.in" > "$rpm_top/SPECS/linux-broadcast.spec"
rpmbuild -bb \
  --define "_topdir $rpm_top" \
  --define '_binary_payload w0.ufdio' \
  "$rpm_top/SPECS/linux-broadcast.spec"
mv "$rpm_top/RPMS/x86_64/linux-broadcast-$version-1.x86_64.rpm" \
  "$release_dir/linux-broadcast-$version-$series.x86_64.rpm"

(
  cd "$release_dir"
  sha256sum ./*.rpm ./*.deb > SHA256SUMS
)

for artifact in "$release_dir"/*.rpm "$release_dir"/*.deb; do
  [[ -s "$artifact" ]] || { printf 'Release artifact is empty: %s\n' "$artifact" >&2; exit 3; }
done
printf 'Release packages written to %s\n' "$release_dir"
