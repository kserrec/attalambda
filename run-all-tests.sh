#!/usr/bin/env bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")" && pwd)"
racket "$project_root/tooling/prepare-racket-runtime.rkt" --check
test_files=()

while IFS= read -r -d '' test_file; do
  test_files+=("$test_file")
done < <(
  find "$project_root/tests" \
    \( -name '.env' -o -name '*.env' -o -name '.env.*' -o -name '*.env.*' \) -prune -o \
    -type f -name '*-test.rkt' -print0 |
    sort -z
)

if [[ "${#test_files[@]}" -eq 0 ]]; then
  echo "No test files found."
  exit 2
fi

# `raco test` can reuse an unchanged test's bytecode after an imported helper
# changes. Refresh dependency caches before executing any test module.
raco make "${test_files[@]}"

for test_file in "${test_files[@]}"; do
  echo "Running ${test_file#"$project_root/"}"
  raco test "$test_file"
done

racket "$project_root/tooling/check-purity.rkt"
racket "$project_root/tooling/check-boundaries.rkt"

echo "All ${#test_files[@]} test files passed."
