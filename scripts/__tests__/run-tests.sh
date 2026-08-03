#!/usr/bin/env bash
# Run every *.test.sh in this directory. Exit non-zero if any file fails.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
failed=0

for f in "$here"/*.test.sh; do
  [ -e "$f" ] || continue
  printf '%s\n' "$(basename "$f")"
  if ! bash "$f"; then
    failed=$((failed + 1))
  fi
done

if [ "$failed" -ne 0 ]; then
  printf '\n%s test file(s) FAILED\n' "$failed"
  exit 1
fi

printf '\nall test files passed\n'
