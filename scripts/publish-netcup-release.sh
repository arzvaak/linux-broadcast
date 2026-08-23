#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(node -p "require('$project_root/ui/src-tauri/tauri.conf.json').version")"
release_root="$project_root/build/releases/$version"
remote="${LINUX_BROADCAST_RELEASE_HOST:-Netcup}"
remote_release="/var/www/linux-broadcast/releases/v$version"

[[ -d "$release_root" ]] || { printf 'Release directory not found: %s\n' "$release_root" >&2; exit 2; }
artifacts=()
for extension in tar rpm deb; do
  mapfile -t format_artifacts < <(find "$release_root" -type f -name "*.$extension" | sort)
  artifacts+=("${format_artifacts[@]}")
done
[[ "${#artifacts[@]}" -eq 12 ]] || {
  printf 'Expected 12 RPM, DEB, and portable artifacts; found %s\n' "${#artifacts[@]}" >&2
  exit 2
}

for artifact in "${artifacts[@]}"; do
  case "$(basename "$artifact")" in
    *rtx20*) series=rtx20 ;;
    *rtx30*) series=rtx30 ;;
    *rtx40*) series=rtx40 ;;
    *rtx50*) series=rtx50 ;;
    *) printf 'Could not determine GPU series for %s\n' "$artifact" >&2; exit 2 ;;
  esac
  "$project_root/scripts/verify-release-artifact.sh" "$artifact" "$series"
done

manifest_dir="$(mktemp -d "$project_root/build/publish.XXXXXX")"
trap 'cmake -E remove_directory "$manifest_dir"' EXIT
for artifact in "${artifacts[@]}"; do
  checksum="$(sha256sum "$artifact" | cut -d' ' -f1)"
  printf '%s  %s\n' "$checksum" "$(basename "$artifact")" >> "$manifest_dir/SHA256SUMS"
done

ssh "$remote" "install -d '$remote_release'"
for extension in tar rpm deb; do
  mapfile -t format_artifacts < <(find "$release_root" -type f -name "*.$extension" | sort)
  rsync -ah --partial-dir=.rsync-partial --fuzzy --info=progress2 "${format_artifacts[@]}" \
    "$remote:$remote_release/"
done
rsync -ah "$manifest_dir/SHA256SUMS" "$remote:$remote_release/"
ssh "$remote" "cd '$remote_release' && sha256sum -c SHA256SUMS"

printf 'Published Linux Broadcast %s to https://arzvak.com/downloads/linux-broadcast/v%s/\n' \
  "$version" "$version"
