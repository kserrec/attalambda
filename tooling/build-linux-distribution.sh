#!/usr/bin/env bash

set -euo pipefail

export LC_ALL=C
umask 022

program_name="build-linux-distribution"
target_identifier="linux-x86_64"
required_racket_banner="Welcome to Racket v9.3 [cs]."
required_racket_version="9.3"
approved_notice_sha256="516b3a08454709bf111494c92ed260a5c4afb47c91d06efca924b500c89e17ad"

usage() {
  cat <<'USAGE'
Usage:
  tooling/build-linux-distribution.sh [--allow-dirty] OUTPUT_DIRECTORY

Build the final Linux x86-64 release archive with Racket CS 9.3. The output
directory must be outside the source checkout and must not already contain the
versioned archive or SHA256SUMS.
USAGE
}

die() {
  printf '%s: %s\n' "$program_name" "$1" >&2
  exit 2
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command is unavailable: $1"
}

dotenv_name_expression=(
  -iname '.env' -o
  -iname '*.env' -o
  -iname '.env.*' -o
  -iname '*.env.*'
)

git_safe_pathspec=(
  .
  ':(exclude,icase,glob).env'
  ':(exclude,icase,glob)*.env'
  ':(exclude,icase,glob).env.*'
  ':(exclude,icase,glob)*.env.*'
  ':(exclude,icase,glob)**/.env'
  ':(exclude,icase,glob)**/*.env'
  ':(exclude,icase,glob)**/.env.*'
  ':(exclude,icase,glob)**/*.env.*'
)

allow_dirty=false
if [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
elif [[ "${1:-}" == "--allow-dirty" ]]; then
  allow_dirty=true
  shift
fi

[[ "$#" -eq 1 ]] || {
  usage >&2
  exit 2
}

output_argument="$1"
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

for command_name in awk basename cat chmod env find git grep gzip install ldd mkdir mktemp mv paste realpath rm sed sha256sum sort stat tar touch uname wc; do
  require_command "$command_name"
done

[[ "$(uname -s)" == "Linux" ]] || die "target requires Linux"
[[ "$(uname -m)" == "x86_64" ]] || die "target requires x86_64"

output_candidate="$(realpath -m -- "$output_argument")"
if [[ "$output_candidate" == "$project_root" ||
      "$output_candidate" == "$project_root/"* ]]; then
  die "OUTPUT_DIRECTORY must be outside the source checkout"
fi
mkdir -p -- "$output_candidate"
output_directory="$(cd "$output_candidate" && pwd -P)"
if [[ "$output_directory" == "$project_root" ||
      "$output_directory" == "$project_root/"* ]]; then
  die "OUTPUT_DIRECTORY resolves inside the source checkout"
fi

version_file="$project_root/VERSION"
info_file="$project_root/info.rkt"
[[ -f "$version_file" && ! -L "$version_file" ]] || die "VERSION must be a regular nonsymlink file"
[[ -f "$info_file" && ! -L "$info_file" ]] || die "info.rkt must be a regular nonsymlink file"

product_version="$(<"$version_file")"
case "$product_version" in
  0.2.0-dev) expected_package_version="0.1.900" ;;
  0.2.0-rc.1) expected_package_version="0.1.901" ;;
  0.2.0) expected_package_version="0.2" ;;
  0.3.0-dev) expected_package_version="0.2.900" ;;
  0.3.0) expected_package_version="0.3" ;;
  0.4.0) expected_package_version="0.4" ;;
  *) die "VERSION is outside the approved milestone states" ;;
esac

expected_version_bytes=$(( ${#product_version} + 1 ))
[[ "$(stat -c '%s' "$version_file")" -eq "$expected_version_bytes" ]] ||
  die "VERSION must contain exactly the product version followed by one LF"
[[ "$(grep -Fxc "(define version \"$expected_package_version\")" "$info_file")" -eq 1 ]] ||
  die "info.rkt does not contain the approved VERSION projection"

artifact_root_name="attalambda-$product_version-$target_identifier"
archive_name="$artifact_root_name.tar.gz"
archive_path="$output_directory/$archive_name"
checksum_path="$output_directory/SHA256SUMS"
verify_command="awk '\$2 == \"$archive_name\" { print }' SHA256SUMS | sha256sum -c -"
[[ ! -e "$archive_path" && ! -L "$archive_path" ]] || die "refusing to replace existing output: $archive_path"
[[ ! -e "$checksum_path" && ! -L "$checksum_path" ]] || die "refusing to replace existing output: $checksum_path"

racket_executable="$(command -v racket)"
raco_executable="$(command -v raco)"
[[ "$("$racket_executable" --version)" == "$required_racket_banner" ]] ||
  die "build requires exactly $required_racket_banner"
[[ "$("$racket_executable" -e '(display (system-type (quote vm)))')" == "chez-scheme" ]] ||
  die "build requires the Racket CS virtual machine"

build_temp_root="$(mktemp -d /tmp/attalambda-linux-build-XXXXXX)"
staged_archive=""
staged_checksum=""
archive_created_by_script=false
checksum_created_by_script=false
outputs_complete=false

cleanup() {
  if [[ -n "${build_temp_root:-}" &&
        "$build_temp_root" == /tmp/attalambda-linux-build-* &&
        -d "$build_temp_root" ]]; then
    rm -rf -- "$build_temp_root"
  fi
  if [[ -n "$staged_archive" ]]; then
    rm -f -- "$staged_archive"
  fi
  if [[ -n "$staged_checksum" ]]; then
    rm -f -- "$staged_checksum"
  fi
  if [[ "$outputs_complete" != true ]]; then
    if [[ "$archive_created_by_script" == true ]]; then
      rm -f -- "$archive_path"
    fi
    if [[ "$checksum_created_by_script" == true ]]; then
      rm -f -- "$checksum_path"
    fi
  fi
}
trap cleanup EXIT

staged_archive="$(mktemp "$output_directory/.${archive_name}.building.XXXXXX")"
staged_checksum="$(mktemp "$output_directory/.SHA256SUMS.building.XXXXXX")"

isolated_user_home="$build_temp_root/racket-user"
isolated_temp_directory="$build_temp_root/tmp"
package_source="$build_temp_root/package-source"
compiled_executable="$build_temp_root/attalambda"
artifact_parent="$build_temp_root/artifact"
artifact_root="$artifact_parent/$artifact_root_name"
mkdir -p -- "$isolated_user_home" "$isolated_temp_directory" "$package_source" "$artifact_parent"

racket_environment=(
  env
  -u PLTCOLLECTS
  -u PLTADDONDIR
  -u PLTCONFIGDIR
  "PLTUSERHOME=$isolated_user_home"
  "TMPDIR=$isolated_temp_directory"
  SOURCE_DATE_EPOCH=0
)

"${racket_environment[@]}" "$racket_executable" -e '(require lazy)' >/dev/null
full_distribution="$("${racket_environment[@]}" "$raco_executable" pkg show --all --rx '^main-distribution$')"
grep -Eq '^[[:space:]]*main-distribution([*[:space:]]|$)' <<<"$full_distribution" ||
  die "build requires the full Racket distribution"

source_commit="$(git -C "$project_root" rev-parse --verify HEAD)"
[[ "$source_commit" =~ ^[0-9a-f]{40}$ ]] || die "could not determine the source commit"

source_tree_dirty=false
if ! git -C "$project_root" diff --quiet -- "${git_safe_pathspec[@]}" ||
   ! git -C "$project_root" diff --cached --quiet -- "${git_safe_pathspec[@]}"; then
  source_tree_dirty=true
fi
untracked_sources="$(git -C "$project_root" ls-files --others --exclude-standard -- "${git_safe_pathspec[@]}")"
if [[ -n "$untracked_sources" ]]; then
  source_tree_dirty=true
fi
if [[ "$source_tree_dirty" == true && "$allow_dirty" != true ]]; then
  die "source tree has uncommitted changes; commit them or use --allow-dirty for internal testing"
fi
if [[ "$source_tree_dirty" == true ]]; then
  source_tree_state="uncommitted changes allowed for internal development testing"
else
  source_tree_state="clean"
fi

copy_regular_file() {
  local relative_path="$1"
  local source_path="$project_root/$relative_path"
  local target_path="$package_source/$relative_path"
  [[ -f "$source_path" && ! -L "$source_path" ]] ||
    die "package input must be a regular nonsymlink file: $relative_path"
  install -D -m 0644 -- "$source_path" "$target_path"
}

copy_regular_file "info.rkt"
copy_regular_file "VERSION"

for source_directory_name in core effects lang macros runner runtime; do
  source_directory="$project_root/$source_directory_name"
  [[ -d "$source_directory" && ! -L "$source_directory" ]] ||
    die "package source directory is unavailable or symlinked: $source_directory_name"
  while IFS= read -r -d '' source_path; do
    relative_path="${source_path#"$project_root/"}"
    if [[ -L "$source_path" ]]; then
      die "package source contains a symlink: $relative_path"
    fi
    [[ "$relative_path" == *.rkt ]] ||
      die "unexpected non-Racket package source: $relative_path"
    install -D -m 0644 -- "$source_path" "$package_source/$relative_path"
  done < <(
    find "$source_directory" \
      \( "${dotenv_name_expression[@]}" -o -name compiled \) -prune -o \
      \( -type f -o -type l \) -print0 |
      sort -z
  )
done

while IFS= read -r -d '' staged_path; do
  touch -h -d '@0' -- "$staged_path"
done < <(
  find "$package_source" \
    \( "${dotenv_name_expression[@]}" \) -prune -o -print0 |
    sort -z
)

"${racket_environment[@]}" "$raco_executable" pkg install \
  --batch \
  --scope user \
  --copy \
  --name attalambda \
  --deps fail \
  --no-docs \
  --fail-fast \
  "$package_source"

"${racket_environment[@]}" "$raco_executable" exe \
  -o "$compiled_executable" \
  ++lang attalambda \
  "$package_source/runner/attalambda.rkt"

[[ "$("${racket_environment[@]}" "$compiled_executable" --version)" == \
    "AttaLambda $product_version" ]] ||
  die "compiled runner version does not match VERSION"

"${racket_environment[@]}" "$raco_executable" distribute \
  "$artifact_root" \
  "$compiled_executable"

[[ -x "$artifact_root/bin/attalambda" && ! -L "$artifact_root/bin/attalambda" ]] ||
  die "raco distribute did not produce bin/attalambda"
[[ -d "$artifact_root/lib" && ! -L "$artifact_root/lib" ]] ||
  die "raco distribute did not produce lib/"

mkdir -p -- "$artifact_root/examples"
for example_name in hello.attl stdout.attl file-round-trip.attl http-server.attl foundations.attl; do
  example_source="$project_root/examples/$example_name"
  [[ -f "$example_source" && ! -L "$example_source" ]] ||
    die "canonical example is unavailable or symlinked: $example_name"
  install -m 0644 -- "$example_source" "$artifact_root/examples/$example_name"
done

for asset_name in GETTING_STARTED.md.in THIRD_PARTY_NOTICES.md.in; do
  asset_path="$project_root/distribution/$asset_name"
  [[ -f "$asset_path" && ! -L "$asset_path" ]] ||
    die "distribution asset is unavailable or symlinked: $asset_name"
done
[[ -f "$project_root/LICENSE" && ! -L "$project_root/LICENSE" ]] ||
  die "repository LICENSE is unavailable or symlinked"

sed \
  -e "s~@VERSION@~$product_version~g" \
  -e "s~@TARGET_NAME@~Linux x86-64~g" \
  -e "s~@ARCHIVE_NAME@~$archive_name~g" \
  -e "s~@COMMAND_LANGUAGE@~sh~g" \
  -e "s~@VERIFY_COMMAND@~$verify_command~g" \
  -e "s~@EXTRACT_COMMAND@~tar -xzf $archive_name~g" \
  -e "s~@ENTER_COMMAND@~cd $artifact_root_name~g" \
  -e "s~@EXECUTABLE@~./bin/attalambda~g" \
  -e "s~@PATH_SEPARATOR@~/~g" \
  -e "s~@DEPENDENCY_KIND@~Linux system-library assumptions~g" \
  "$project_root/distribution/GETTING_STARTED.md.in" \
  > "$artifact_root/GETTING_STARTED.md"
grep -Eq '@[A-Z_]+@' "$artifact_root/GETTING_STARTED.md" &&
  die "unexpanded getting-started placeholder"
install -m 0644 -- "$project_root/LICENSE" "$artifact_root/LICENSE"
license_digest="$(sha256sum "$project_root/LICENSE" | awk '{print $1}')"
notice_path="$project_root/distribution/THIRD_PARTY_NOTICES.md.in"
notice_digest="$(sha256sum "$notice_path" | awk '{print $1}')"
[[ "$notice_digest" == "$approved_notice_sha256" ]] ||
  die "third-party notices differ from the exact Phase 29 approval"
install -m 0644 -- "$notice_path" "$artifact_root/THIRD_PARTY_NOTICES.md"

runtime_files=("$artifact_root"/lib/plt/racketcs-*)
[[ "${#runtime_files[@]}" -eq 1 && -f "${runtime_files[0]}" && ! -L "${runtime_files[0]}" ]] ||
  die "expected exactly one distributed Racket CS runtime file"

dynamic_libraries_file="$build_temp_root/dynamic-libraries.txt"
: > "$dynamic_libraries_file"
for executable_path in "$artifact_root/bin/attalambda" "${runtime_files[0]}"; do
  ldd_output="$build_temp_root/ldd-$(basename "$executable_path").txt"
  ldd "$executable_path" > "$ldd_output"
  grep -Fq 'not found' "$ldd_output" &&
    die "distributed executable has an unresolved dynamic library"
  awk '
    /=>/ { print $1; next }
    /^[[:space:]]*\// {
      name=$1
      sub(/^.*\//, "", name)
      print name
    }
  ' "$ldd_output" >> "$dynamic_libraries_file"
done
runtime_file_name="$(basename "${runtime_files[0]}")"
grep -Fvx "$runtime_file_name" "$dynamic_libraries_file" |
  sort -u > "$dynamic_libraries_file.sorted"
mv -- "$dynamic_libraries_file.sorted" "$dynamic_libraries_file"
[[ -s "$dynamic_libraries_file" ]] || die "dynamic system-library inventory is empty"

manifest_path="$artifact_root/BUILD-MANIFEST.txt"
: > "$manifest_path"
artifact_inventory_file="$build_temp_root/artifact-inventory.txt"
find "$artifact_root" \
  \( "${dotenv_name_expression[@]}" \) -prune -o \
  -type f -printf '%P\n' |
  sort > "$artifact_inventory_file"

{
  printf 'AttaLambda build manifest\n'
  printf 'Manifest format: 1\n'
  printf 'Product version: %s\n' "$product_version"
  printf 'Source commit: %s\n' "$source_commit"
  printf 'Source tree state: %s\n' "$source_tree_state"
  printf 'Target identifier: %s\n' "$target_identifier"
  printf 'Racket version: %s\n' "$required_racket_version"
  printf 'Racket variant: CS\n'
  printf 'Artifact status: final release artifact\n'
  printf 'Repository license SHA-256: %s\n' "$license_digest"
  printf 'Third-party notices SHA-256: %s\n' "$notice_digest"
  printf 'Archive checksum: external sibling SHA256SUMS\n'
  printf '\nArtifact file inventory:\n'
  sed 's/^/  /' "$artifact_inventory_file"
  printf '\nObserved dynamic system-library assumptions:\n'
  sed 's/^/  /' "$dynamic_libraries_file"
} > "$manifest_path"

while IFS= read -r -d '' linked_path; do
  die "artifact contains a symlink: ${linked_path#"$artifact_root/"}"
done < <(
  find "$artifact_root" \
    \( "${dotenv_name_expression[@]}" \) -prune -o \
    -type l -print0
)

scan_for_build_path() {
  local forbidden_path="$1"
  [[ -n "$forbidden_path" ]] || return 0
  while IFS= read -r -d '' artifact_file; do
    if grep -aFq -- "$forbidden_path" "$artifact_file"; then
      die "artifact retains a forbidden build path"
    fi
  done < <(
    find "$artifact_root" \
      \( "${dotenv_name_expression[@]}" \) -prune -o \
      -type f -print0
  )
}

scan_for_build_path "$project_root"
scan_for_build_path "$build_temp_root"
toolchain_root="$(dirname "$(dirname "$(realpath "$racket_executable")")")"
case "$toolchain_root" in
  /usr|/usr/local)
    # A system-wide Unix-style installation uses an ordinary system prefix. The
    # no-Racket consumer proves that the artifact does not depend on it.
    :
    ;;
  *) scan_for_build_path "$toolchain_root" ;;
esac

[[ "$(env -u PLTCOLLECTS -u PLTADDONDIR -u PLTCONFIGDIR \
          "$artifact_root/bin/attalambda" --version)" == \
    "AttaLambda $product_version" ]] ||
  die "distributed runner version does not match VERSION"

while IFS= read -r -d '' artifact_path; do
  touch -h -d '@0' -- "$artifact_path"
done < <(
  find "$artifact_root" \
    \( "${dotenv_name_expression[@]}" \) -prune -o -print0 |
    sort -z
)

tar --version | grep -Fq 'GNU tar' || die "deterministic Linux archive requires GNU tar"
tar \
  --sort=name \
  --format=posix \
  --pax-option=delete=atime,delete=ctime \
  --mtime='@0' \
  --owner=0 \
  --group=0 \
  --numeric-owner \
  -C "$artifact_parent" \
  -cf - \
  "$artifact_root_name" |
  gzip -n -9 > "$staged_archive"

archive_digest="$(sha256sum "$staged_archive" | awk '{print $1}')"
printf '%s  %s\n' "$archive_digest" "$archive_name" > "$staged_checksum"
chmod 0644 -- "$staged_archive" "$staged_checksum"

archive_bytes="$(stat -c '%s' "$staged_archive")"
unpacked_bytes="$(find "$artifact_root" \
  \( "${dotenv_name_expression[@]}" \) -prune -o \
  -type f -printf '%s\n' | awk '{ total += $1 } END { print total + 0 }')"
artifact_file_count="$(wc -l < "$artifact_inventory_file")"
runtime_file_count="$(find "$artifact_root/bin" "$artifact_root/lib" \
  \( "${dotenv_name_expression[@]}" \) -prune -o \
  -type f -printf '.\n' | wc -l)"

mv -n -- "$staged_archive" "$archive_path"
[[ ! -e "$staged_archive" && -f "$archive_path" && ! -L "$archive_path" ]] ||
  die "archive output appeared concurrently; no existing file was replaced"
staged_archive=""
archive_created_by_script=true
mv -n -- "$staged_checksum" "$checksum_path"
[[ ! -e "$staged_checksum" && -f "$checksum_path" && ! -L "$checksum_path" ]] ||
  die "checksum output appeared concurrently; no existing file was replaced"
staged_checksum=""
checksum_created_by_script=true
outputs_complete=true

printf 'archive=%s\n' "$archive_path"
printf 'checksum_manifest=%s\n' "$checksum_path"
printf 'sha256=%s\n' "$archive_digest"
printf 'compressed_bytes=%s\n' "$archive_bytes"
printf 'unpacked_regular_file_bytes=%s\n' "$unpacked_bytes"
printf 'artifact_files=%s\n' "$artifact_file_count"
printf 'runtime_files=%s\n' "$runtime_file_count"
printf 'system_libraries=%s\n' "$(paste -sd, "$dynamic_libraries_file")"
