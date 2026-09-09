#!/usr/bin/env bash

set -euo pipefail

export LC_ALL=C

program_name="test-linux-distribution"
consumer_image="ubuntu:24.04@sha256:561618e2c15bf2397621dd04f96926663a3b5616c189cf7e38db7e82f5c538ea"

usage() {
  cat <<'USAGE'
Usage:
  tooling/test-linux-distribution.sh OUTPUT_DIRECTORY

Transfer the final Linux release archive and its checksum into
a locked-down Ubuntu 24.04 container with no Racket installation, then run the
Phase 29 guide, consumer, and relocation acceptance checks.
USAGE
}

die() {
  printf '%s: %s\n' "$program_name" "$1" >&2
  exit 2
}

dotenv_component() {
  local lower_path="${1,,}"
  [[ "/$lower_path/" =~ /([^/]*\.)?env(\.[^/]*)?/ ]]
}

dotenv_name_expression=(
  -iname '.env' -o
  -iname '*.env' -o
  -iname '.env.*' -o
  -iname '*.env.*'
)

run_inside_consumer() {
  [[ "$#" -eq 3 ]] || die "internal consumer arguments are invalid"
  local archive_name="$1"
  local artifact_root_name="$2"
  local product_version="$3"
  local transfer_directory="/transfer"
  local archive_path="$transfer_directory/$archive_name"
  local checksum_path="$transfer_directory/SHA256SUMS"
  local scratch_root="/tmp/attalambda-consumer"
  local first_parent="$scratch_root/first path with spaces"
  local first_root="$first_parent/$artifact_root_name"
  local second_parent="$scratch_root/second relocated path"
  local second_root="$second_parent/$artifact_root_name"
  local server_pid=""

  cleanup_consumer() {
    if [[ -n "${server_pid:-}" ]] && kill -0 "$server_pid" 2>/dev/null; then
      kill "$server_pid" 2>/dev/null || true
      wait "$server_pid" 2>/dev/null || true
    fi
  }
  trap cleanup_consumer EXIT

  command -v racket >/dev/null 2>&1 && die "consumer unexpectedly has a racket command"
  command -v raco >/dev/null 2>&1 && die "consumer unexpectedly has a raco command"
  [[ -f "$archive_path" && ! -L "$archive_path" ]] || die "transferred archive is unavailable"
  [[ -f "$checksum_path" && ! -L "$checksum_path" ]] || die "transferred checksum manifest is unavailable"

  local expected_checksum_line
  expected_checksum_line="$(<"$checksum_path")"
  [[ "$expected_checksum_line" =~ ^[0-9a-f]{64}[[:space:]][[:space:]]${archive_name//./\.}$ ]] ||
    die "checksum manifest does not contain exactly the transferred archive"
  (cd "$transfer_directory" && sha256sum -c SHA256SUMS >/dev/null)

  while IFS= read -r archive_entry; do
    [[ "$archive_entry" == "$artifact_root_name" ||
       "$archive_entry" == "$artifact_root_name/"* ]] ||
      die "archive contains an entry outside its one root directory"
    [[ "$archive_entry" != /* &&
       "/$archive_entry/" != *'/../'* ]] ||
      die "archive contains an unsafe path"
    dotenv_component "$archive_entry" && die "archive contains a dotenv path"
  done < <(tar -tzf "$archive_path")

  mkdir -p -- "$first_parent"
  cp -- "$archive_path" "$first_parent/$archive_name"
  cp -- "$checksum_path" "$first_parent/SHA256SUMS"
  (
    cd "$first_parent"
    awk '$2 == "'"$archive_name"'" { print }' SHA256SUMS | sha256sum -c -
    tar -xzf "$archive_name"
  )
  [[ -d "$first_root" && ! -L "$first_root" ]] || die "archive root is unavailable"

  while IFS= read -r -d '' linked_path; do
    die "extracted artifact contains a symlink"
  done < <(
    find "$first_root" \
      \( "${dotenv_name_expression[@]}" \) -prune -o \
      -type l -print0
  )

  for required_path in \
    bin/attalambda \
    examples/hello.attl \
    examples/stdout.attl \
    examples/file-round-trip.attl \
    examples/http-server.attl \
    examples/foundations.attl \
    GETTING_STARTED.md \
    BUILD-MANIFEST.txt \
    LICENSE \
    THIRD_PARTY_NOTICES.md; do
    [[ -f "$first_root/$required_path" && ! -L "$first_root/$required_path" ]] ||
      die "artifact is missing required file: $required_path"
  done
  [[ -d "$first_root/lib" && ! -L "$first_root/lib" ]] || die "artifact is missing lib/"
  [[ -x "$first_root/bin/attalambda" ]] || die "bin/attalambda is not executable"
  [[ ! -e "$first_root/UNPUBLISHED-DEVELOPMENT-ARTIFACT.txt" &&
     ! -L "$first_root/UNPUBLISHED-DEVELOPMENT-ARTIFACT.txt" ]] ||
    die "release archive contains the retired development warning"

  local actual_top_level="$scratch_root/actual-top-level.txt"
  local expected_top_level="$scratch_root/expected-top-level.txt"
  find "$first_root" -mindepth 1 -maxdepth 1 \
    \( "${dotenv_name_expression[@]}" \) -prune -o \
    -printf '%f\n' |
    sort > "$actual_top_level"
  printf '%s\n' \
    BUILD-MANIFEST.txt \
    GETTING_STARTED.md \
    LICENSE \
    THIRD_PARTY_NOTICES.md \
    bin \
    examples \
    lib |
    sort > "$expected_top_level"
  cmp -s "$actual_top_level" "$expected_top_level" ||
    die "artifact top-level layout differs from the contract"

  local actual_bin="$scratch_root/actual-bin.txt"
  local actual_examples="$scratch_root/actual-examples.txt"
  find "$first_root/bin" -mindepth 1 -maxdepth 1 \
    \( "${dotenv_name_expression[@]}" \) -prune -o \
    -printf '%f\n' |
    sort > "$actual_bin"
  printf '%s\n' attalambda > "$scratch_root/expected-bin.txt"
  cmp -s "$actual_bin" "$scratch_root/expected-bin.txt" ||
    die "artifact bin/ inventory differs from the contract"
  find "$first_root/examples" -mindepth 1 -maxdepth 1 \
    \( "${dotenv_name_expression[@]}" \) -prune -o \
    -printf '%f\n' |
    sort > "$actual_examples"
  printf '%s\n' file-round-trip.attl foundations.attl hello.attl http-server.attl stdout.attl \
    > "$scratch_root/expected-examples.txt"
  cmp -s "$actual_examples" "$scratch_root/expected-examples.txt" ||
    die "artifact examples/ inventory differs from the contract"

  local actual_inventory="$scratch_root/actual-inventory.txt"
  local manifest_inventory="$scratch_root/manifest-inventory.txt"
  find "$first_root" \
    \( "${dotenv_name_expression[@]}" \) -prune -o \
    -type f -printf '%P\n' |
    sort > "$actual_inventory"
  local artifact_file_count
  local unpacked_regular_file_bytes
  local runtime_file_count
  artifact_file_count="$(wc -l < "$actual_inventory")"
  unpacked_regular_file_bytes="$(
    find "$first_root" \
      \( "${dotenv_name_expression[@]}" \) -prune -o \
      -type f -printf '%s\n' |
      awk '{ total += $1 } END { print total }'
  )"
  runtime_file_count="$(
    find "$first_root/bin" "$first_root/lib" \
      \( "${dotenv_name_expression[@]}" \) -prune -o \
      -type f -printf '.\n' |
      wc -l
  )"
  awk '
    /^Artifact file inventory:$/ { inventory=1; next }
    /^Observed dynamic system-library assumptions:$/ { inventory=0 }
    inventory && /^  / { sub(/^  /, ""); print }
  ' "$first_root/BUILD-MANIFEST.txt" > "$manifest_inventory"
  cmp -s "$actual_inventory" "$manifest_inventory" ||
    die "BUILD-MANIFEST.txt file inventory differs from the artifact"

  grep -Fxq "Product version: $product_version" "$first_root/BUILD-MANIFEST.txt" ||
    die "build manifest version mismatch"
  grep -Fxq 'Target identifier: linux-x86_64' "$first_root/BUILD-MANIFEST.txt" ||
    die "build manifest target mismatch"
  grep -Fxq 'Racket version: 9.3' "$first_root/BUILD-MANIFEST.txt" ||
    die "build manifest Racket version mismatch"
  grep -Fxq 'Racket variant: CS' "$first_root/BUILD-MANIFEST.txt" ||
    die "build manifest Racket variant mismatch"
  grep -Eq '^Source commit: [0-9a-f]{40}$' "$first_root/BUILD-MANIFEST.txt" ||
    die "build manifest source commit is invalid"
  grep -Fxq 'Archive checksum: external sibling SHA256SUMS' "$first_root/BUILD-MANIFEST.txt" ||
    die "build manifest checksum contract mismatch"
  grep -Fxq 'Artifact status: final release artifact' "$first_root/BUILD-MANIFEST.txt" ||
    die "build manifest release status mismatch"
  grep -Fxq 'Repository license SHA-256: cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30' "$first_root/BUILD-MANIFEST.txt" ||
    die "build manifest repository-license hash mismatch"
  grep -Fxq 'Third-party notices SHA-256: 516b3a08454709bf111494c92ed260a5c4afb47c91d06efca924b500c89e17ad' "$first_root/BUILD-MANIFEST.txt" ||
    die "build manifest notice hash mismatch"
  [[ "$(sha256sum "$first_root/LICENSE" | awk '{print $1}')" == \
      "cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30" ]] ||
    die "repository license bytes differ from the approved license"
  [[ "$(sha256sum "$first_root/THIRD_PARTY_NOTICES.md" | awk '{print $1}')" == \
      "516b3a08454709bf111494c92ed260a5c4afb47c91d06efca924b500c89e17ad" ]] ||
    die "third-party notices differ from the exact Phase 29 approval"
  grep -Fxq "awk '\$2 == \"$archive_name\" { print }' SHA256SUMS | sha256sum -c -" "$first_root/GETTING_STARTED.md" ||
    die "guide checksum command mismatch"
  grep -Fxq "tar -xzf $archive_name" "$first_root/GETTING_STARTED.md" ||
    die "guide extraction command mismatch"
  grep -Fxq "cd $artifact_root_name" "$first_root/GETTING_STARTED.md" ||
    die "guide directory command mismatch"
  grep -Fxq './bin/attalambda --version' "$first_root/GETTING_STARTED.md" ||
    die "guide version command mismatch"
  grep -Fxq './bin/attalambda examples/hello.attl' "$first_root/GETTING_STARTED.md" ||
    die "guide hello command mismatch"
  grep -Fxq './bin/attalambda my-program.attl' "$first_root/GETTING_STARTED.md" ||
    die "guide custom-program command mismatch"

  local attalambda="$first_root/bin/attalambda"
  local stdout_file="$scratch_root/stdout.txt"
  local stderr_file="$scratch_root/stderr.txt"
  local expected_file="$scratch_root/expected-output.txt"

  check_captured_output() {
    local expected_output="$1"
    local failure_label="$2"
    printf '%s' "$expected_output" > "$expected_file"
    cmp -s "$stdout_file" "$expected_file" || die "$failure_label output mismatch"
    [[ ! -s "$stderr_file" ]] || die "$failure_label wrote stderr"
  }

  local first_startup_begin
  local first_startup_end
  local first_startup_milliseconds
  first_startup_begin="$(date +%s%N)"
  (
    cd "$first_parent"
    cd "$artifact_root_name"
    ./bin/attalambda --version >"$stdout_file" 2>"$stderr_file"
  )
  first_startup_end="$(date +%s%N)"
  first_startup_milliseconds=$(( (first_startup_end - first_startup_begin + 999999) / 1000000 ))
  check_captured_output "AttaLambda $product_version"$'\n' "packaged version"

  "$attalambda" --help >"$stdout_file" 2>"$stderr_file"
  check_captured_output \
    $'Usage:\n  attalambda FILE.attl\n  attalambda --help\n  attalambda --version\n' \
    "packaged help"

  (cd "$first_root" && ./bin/attalambda examples/hello.attl \
    >"$stdout_file" 2>"$stderr_file")
  check_captured_output $'Hello from AttaLambda.\n' "guide hello"

  printf '%s\n' \
    '#lang attalambda' \
    '' \
    '(stdout "My first AttaLambda program.\n")' \
    > "$first_root/my-program.attl"
  (cd "$first_root" && ./bin/attalambda my-program.attl \
    >"$stdout_file" 2>"$stderr_file")
  check_captured_output $'My first AttaLambda program.\n' "guide custom program"

  local generated_source="$scratch_root/generated-after-packaging.attl"
  printf '%s\n' \
    '#lang attalambda' \
    '' \
    '(stdout "Generated after packaging.\n")' \
    > "$generated_source"
  "$attalambda" "$generated_source" >"$stdout_file" 2>"$stderr_file"
  check_captured_output $'Generated after packaging.\n' "generated source"

  local public_api_source="$scratch_root/public-api.attl"
  cat > "$public_api_source" <<'PROGRAM'
#lang attalambda

(def check condition = (stdout (if condition "." "!")))
(def values = (cons 1 (cons 2 (cons 3 NIL))))
(def nested = (cons (cons 1 (cons (cons 2 NIL) NIL)) (cons (cons 3 NIL) NIL)))
(rec loop value = (loop value))
(rec countdown count answer =
  (if (eq count 0) answer (countdown (sub count 1) answer)))
(def a = 1)
(def x = 2)
(def n = 3)
(def m = 4)

(check (eq (head values) 1))
(check (eq (head (tail values)) 2))
(check (eq (len values) 3))
(check (eq (len (take 2 values)) 2))
(check (is-nil (drop 3 values)))
(check (option-case (nth 1 values) (eq 2) FALSE))
(check (eq (len (take-while (lt 1) values)) 0))
(check (eq (head (drop-while (eq 1) values)) 2))
(check (eq (len (append values (cons 4 NIL))) 4))
(check (eq (head (reverse values)) 3))
(check (eq (head (tail (head (zip values (reverse values))))) 3))
(check (eq (len (concat nested)) 3))
(check (eq (head (head (tail (concat nested)))) 2))
(check (eq (reduce add 0 (flatten nested)) 6))
(check (eq (reduce add 0 (map succ values)) 9))
(check (eq (head (filter (lambda (value) (gt value 1)) values)) 2))
(check (eq (reduce sub 10 values) 4))
(check (any? (eq 2) values))
(check (all? (lambda (value) (lt value 4)) values))
(check (option-case (find (eq 2) values) (eq 2) FALSE))
(check (option-case (find-index (eq 2) values) (eq 1) FALSE))
(check (contains? eq 2 values))
(check (and (eq (reduce add 0 (range -2 3)) 0) (eq (len (range -2 3)) 5)))
(check (string-eq (make-string (repeat 3 #\x)) "xxx"))
(check (is-nil (repeat 0 (loop NIL))))
(check (and (eq a 1) (and (eq x 2) (and (eq n 3) (eq m 4)))))
(check (option-case (map-lookup (map-set (make-map eq) 1 7) 1) (eq 7) FALSE))
(check (and (char-eq #\a (make-char 97)) (char-eq #\A (string-head "A"))))
(check (string-eq (make-string (cons #\( (cons #\) (cons #\space (cons #\tab (cons #\newline (cons #\return NIL))))))) "() \t\n\r"))
(check (any? (lambda (value) (if (eq value 1) TRUE (loop value))) values))
(check (eq ((countdown 3) 7) 7))
PROGRAM
  timeout 20 "$attalambda" "$public_api_source" >"$stdout_file" 2>"$stderr_file"
  check_captured_output '...............................' "packaged public API"
  printf 'packaged_public_api=passed\n'

  local printing_source="$scratch_root/printing-api.attl"
  cat > "$printing_source" <<'PROGRAM'
#lang attalambda

(def check condition = (stdout (if condition "." "!")))
(def nested = (some (make-ok (cons 1 (cons TRUE (cons "hello" NIL))))))
(check (string-eq (rat-to-string -7/3) "-7/3"))
(check (string-eq (bool-to-string TRUE) "TRUE"))
(check (string-eq (unit-to-string UNIT) "UNIT"))
(check (string-eq (byte-to-string (make-byte 255)) "BYTE(255)"))
(check (string-eq (char-to-string #\newline) "#\\newline"))
(check (string-eq (string-to-string "é\n") "\"\\xC3\\xA9\\n\""))
(check (string-eq (list-to-string (cons 1 (cons TRUE NIL))) "[1, TRUE]"))
(check (string-eq (option-to-string (some 5)) "SOME(5)"))
(check (string-eq (result-to-string (div 1 0)) "ERR(ERROR(DIVIDE-BY-ZERO))"))
(check (string-eq (map-to-string (map-set (make-map string-eq) "answer" 42)) "{\"answer\": 42}"))
(check (string-eq (error-to-string (head NIL)) "ERROR(EMPTY-LIST\n  -> head(result))"))
(check (string-eq (value-to-string nested) "SOME(OK([1, TRUE, \"hello\"]))"))
(check (is-ok (print nested)))
(if FALSE (print "unused") UNIT)
(stdout "hello")
(print "hello")
PROGRAM
  timeout 20 "$attalambda" "$printing_source" >"$stdout_file" 2>"$stderr_file"
  check_captured_output '............SOME(OK([1, TRUE, "hello"])).hello"hello"' "packaged printing API"
  printf 'packaged_printing_api=passed\n'

  local sugar_source="$scratch_root/small-lisp-sugar.attl"
  cat > "$sugar_source" <<'PROGRAM'
#lang attalambda
(rec loop x = (loop x))
(def sum = (lambda (x y z) (add x (add y z))))
(def plus-two = (sum 2))
(print (list))
(print (list (list 1 2) (list 3 4)))
(print (list (plus-two 3 4)
             (let ((x 2) (y (add x 3))) y)
             (let x = 6 x)
             ((lambda (x) x) 7)))
(stdout (cond (FALSE (loop NIL)) (TRUE "lazy") (else (loop NIL))))
(print (cond (FALSE 0) (else 8)))
PROGRAM
  timeout 20 "$attalambda" "$sugar_source" >"$stdout_file" 2>"$stderr_file"
  check_captured_output '[][[1, 2], [3, 4]][9, 5, 6, 7]lazy8' "packaged small Lisp sugar"
  printf 'packaged_small_lisp_sugar=passed\n'

  local completion_work="$scratch_root/completion-work"
  mkdir -p -- "$completion_work"
  check_program_status() {
    local label="$1"
    local expected_status="$2"
    local source_body="$3"
    local program="$completion_work/$label.attl"
    local actual_status
    printf '%s\n' '#lang attalambda' "$source_body" > "$program"
    if (cd "$completion_work" && timeout 20 "$attalambda" "$program" \
        >"$stdout_file" 2>"$stderr_file"); then
      actual_status=0
    else
      actual_status=$?
    fi
    [[ "$actual_status" -eq "$expected_status" ]] ||
      die "$label status mismatch: expected $expected_status, got $actual_status"
    check_captured_output '' "$label"
    printf '%s=%s\n' "$label" "$actual_status"
  }

  check_program_status packaged_exit_zero_status 0 '(exit 0)'
  check_program_status packaged_exit_one_status 1 '(exit 1)'
  check_program_status packaged_default_status 0 \
    $'(add TRUE 1)\n(div 1 0)\n(read-file "absent-exit-input.txt")'
  check_program_status packaged_missing_file_fatal_status 1 \
    $'(def outcome = (read-file "absent-exit-input.txt"))\n(if (is-err outcome) (exit 1) (exit 0))'
  check_program_status packaged_missing_file_recoverable_status 0 \
    $'(def outcome = (read-file "absent-exit-input.txt"))\n(if (is-err outcome) (exit 0) (exit 1))'

  local decoy_root="$scratch_root/decoy-collections"
  mkdir -p -- "$decoy_root/attalambda/lang"
  printf '%s\n' 'this external reader must never be loaded' \
    > "$decoy_root/attalambda/lang/reader.rkt"
  PLTCOLLECTS="$decoy_root" "$attalambda" "$generated_source" \
    >"$stdout_file" 2>"$stderr_file"
  check_captured_output $'Generated after packaging.\n' "embedded-language precedence run"

  local stdout_work="$scratch_root/stdout-work"
  mkdir -p -- "$stdout_work"
  (cd "$stdout_work" && "$attalambda" "$first_root/examples/stdout.attl" \
    >"$stdout_file" 2>"$stderr_file")
  check_captured_output $'Hello from AttaLambda.\n' "stdout example"

  local file_work="$scratch_root/file-work"
  mkdir -p -- "$file_work"
  (cd "$file_work" && "$attalambda" "$first_root/examples/file-round-trip.attl" \
    >"$stdout_file" 2>"$stderr_file")
  check_captured_output $'AttaLambda file round trip.\n' "file round trip"
  printf '%s' $'AttaLambda file round trip.\n' > "$expected_file"
  cmp -s "$file_work/attalambda-round-trip.txt" "$expected_file" ||
    die "packaged file round trip wrote the wrong bytes"

  local http_work="$scratch_root/http-work"
  local announcement_file="$scratch_root/http-announcement.txt"
  local http_error_file="$scratch_root/http-stderr.txt"
  local response_file="$scratch_root/http-response.txt"
  mkdir -p -- "$http_work"
  (cd "$http_work" && timeout 20 "$attalambda" "$first_root/examples/http-server.attl" \
    > "$announcement_file" 2> "$http_error_file") &
  server_pid="$!"
  for _attempt in $(seq 1 200); do
    [[ -s "$announcement_file" ]] && break
    kill -0 "$server_pid" 2>/dev/null || break
    sleep 0.05
  done
  local announcement
  announcement="$(<"$announcement_file")"
  [[ "$announcement" =~ ^Listening[[:space:]]on[[:space:]]http://127\.0\.0\.1:([0-9]+)/lambda$ ]] ||
    die "packaged HTTP example did not announce an ephemeral loopback URL"
  local bound_port="${BASH_REMATCH[1]}"
  exec 3<>"/dev/tcp/127.0.0.1/$bound_port"
  printf 'GET /lambda HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n' >&3
  cat <&3 > "$response_file"
  exec 3<&-
  exec 3>&-
  wait "$server_pid"
  server_pid=""
  [[ ! -s "$http_error_file" ]] || die "HTTP example wrote stderr"
  grep -Fq $'HTTP/1.1 200 OK\r' "$response_file" || die "HTTP response status mismatch"
  sed -n '/^\r$/,$p' "$response_file" | sed '1d' > "$scratch_root/http-body.txt"
  printf '%s' $'Hello from AttaLambda.\n' > "$expected_file"
  cmp -s "$scratch_root/http-body.txt" "$expected_file" ||
    die "HTTP response body mismatch"

  mkdir -p -- "$second_parent"
  mv -- "$first_root" "$second_root"
  attalambda="$second_root/bin/attalambda"
  local relocated_startup_begin
  local relocated_startup_end
  local relocated_startup_milliseconds
  relocated_startup_begin="$(date +%s%N)"
  "$attalambda" --version >"$stdout_file" 2>"$stderr_file"
  relocated_startup_end="$(date +%s%N)"
  relocated_startup_milliseconds=$(( (relocated_startup_end - relocated_startup_begin + 999999) / 1000000 ))
  check_captured_output "AttaLambda $product_version"$'\n' "relocated version"
  "$attalambda" "$generated_source" >"$stdout_file" 2>"$stderr_file"
  check_captured_output $'Generated after packaging.\n' "relocated source"

  printf 'consumer_image=%s\n' "$consumer_image"
  printf 'consumer_racket_command=absent\n'
  printf 'consumer_raco_command=absent\n'
  printf 'consumer_network=none-with-loopback-only\n'
  printf 'archive_sha256=%s\n' "${expected_checksum_line%% *}"
  printf 'compressed_bytes=%s\n' "$(stat -c '%s' "$archive_path")"
  printf 'unpacked_regular_file_bytes=%s\n' "$unpacked_regular_file_bytes"
  printf 'artifact_files=%s\n' "$artifact_file_count"
  printf 'runtime_files=%s\n' "$runtime_file_count"
  printf 'guide_workflow=passed\n'
  printf 'relocation=passed\n'
  printf 'first_startup_milliseconds=%s\n' "$first_startup_milliseconds"
  printf 'relocated_startup_milliseconds=%s\n' "$relocated_startup_milliseconds"
  printf 'consumer_acceptance=passed\n'
}

if [[ "${1:-}" == "--inside-consumer" ]]; then
  shift
  run_inside_consumer "$@"
  exit 0
fi

if [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
[[ "$#" -eq 1 ]] || {
  usage >&2
  exit 2
}

for command_name in chmod docker install mktemp realpath sha256sum stat; do
  command -v "$command_name" >/dev/null 2>&1 || die "required command is unavailable: $command_name"
done

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
output_directory="$(realpath -- "$1")"
version_file="$project_root/VERSION"
[[ -f "$version_file" && ! -L "$version_file" ]] || die "VERSION is unavailable or symlinked"
product_version="$(<"$version_file")"
artifact_root_name="attalambda-$product_version-linux-x86_64"
archive_name="$artifact_root_name.tar.gz"
archive_path="$output_directory/$archive_name"
checksum_path="$output_directory/SHA256SUMS"
[[ -f "$archive_path" && ! -L "$archive_path" ]] || die "archive is unavailable: $archive_path"
[[ -f "$checksum_path" && ! -L "$checksum_path" ]] || die "checksum manifest is unavailable: $checksum_path"
[[ "$(stat -c '%a' "$archive_path")" == "644" ]] || die "archive mode must be 0644"
[[ "$(stat -c '%a' "$checksum_path")" == "644" ]] || die "checksum manifest mode must be 0644"

expected_checksum_line="$(<"$checksum_path")"
[[ "$expected_checksum_line" =~ ^[0-9a-f]{64}[[:space:]][[:space:]]${archive_name//./\.}$ ]] ||
  die "SHA256SUMS must contain exactly the versioned Linux archive"
(cd "$output_directory" && sha256sum -c SHA256SUMS >/dev/null)

consumer_transfer_root="$(mktemp -d /tmp/attalambda-linux-transfer-XXXXXX)"
cleanup_host() {
  if [[ -n "${consumer_transfer_root:-}" &&
        "$consumer_transfer_root" == /tmp/attalambda-linux-transfer-* &&
        -d "$consumer_transfer_root" ]]; then
    rm -rf -- "$consumer_transfer_root"
  fi
}
trap cleanup_host EXIT

chmod 0755 -- "$consumer_transfer_root"
install -m 0644 -- "$archive_path" "$consumer_transfer_root/$archive_name"
install -m 0644 -- "$checksum_path" "$consumer_transfer_root/SHA256SUMS"
install -m 0555 -- "${BASH_SOURCE[0]}" "$consumer_transfer_root/consumer.sh"

docker run \
  --rm \
  --pull=missing \
  --platform linux/amd64 \
  --network none \
  --read-only \
  --tmpfs /tmp:rw,exec,nosuid,nodev,mode=1777 \
  --user 65534:65534 \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --pids-limit 256 \
  --memory 2g \
  --mount "type=bind,src=$consumer_transfer_root,dst=/transfer,readonly" \
  --entrypoint /bin/bash \
  "$consumer_image" \
  /transfer/consumer.sh \
  --inside-consumer \
  "$archive_name" \
  "$artifact_root_name" \
  "$product_version"
