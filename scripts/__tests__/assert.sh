# shellcheck shell=bash
# Assertion helpers for the plain-bash test files in this directory.
# Sourced, never executed. No `set -e` here: a failing assertion must record
# the failure and let the file keep running, so one run reports every problem
# rather than only the first.

TESTS_RUN=0
TESTS_FAILED=0

# run_cmd COMMAND [ARGS...]
# Runs the command, capturing combined output in OUT and exit status in RC.
# Never aborts the caller, whatever the command returns.
run_cmd() {
  set +e
  OUT=$("$@" 2>&1)
  RC=$?
  set -e
}

# assert_eq EXPECTED ACTUAL MESSAGE
assert_eq() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$1" = "$2" ]; then
    printf '  ok   %s\n' "$3"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf '  FAIL %s\n' "$3"
    printf '    expected: [%s]\n' "$1"
    printf '    actual:   [%s]\n' "$2"
  fi
}

# assert_rc EXPECTED_CODE MESSAGE   (reads RC set by run_cmd)
assert_rc() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$1" = "$RC" ]; then
    printf '  ok   %s\n' "$2"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf '  FAIL %s\n' "$2"
    printf '    expected exit: %s\n' "$1"
    printf '    actual exit:   %s\n' "$RC"
    printf '    output:        %s\n' "$OUT"
  fi
}

# assert_contains NEEDLE HAYSTACK MESSAGE
# Matching is a shell `case` glob, so a NEEDLE containing '*', '?' or '['
# is a pattern, not a literal. Callers pass needles free of those characters.
assert_contains() {
  TESTS_RUN=$((TESTS_RUN + 1))
  case "$2" in
    *"$1"*)
      printf '  ok   %s\n' "$3"
      ;;
    *)
      TESTS_FAILED=$((TESTS_FAILED + 1))
      printf '  FAIL %s\n' "$3"
      printf '    expected to contain: [%s]\n' "$1"
      printf '    actual:              [%s]\n' "$2"
      ;;
  esac
}

# finish — print the per-file summary and exit non-zero if anything failed.
finish() {
  printf '  %s run, %s failed\n' "$TESTS_RUN" "$TESTS_FAILED"
  [ "$TESTS_FAILED" -eq 0 ] || exit 1
}
