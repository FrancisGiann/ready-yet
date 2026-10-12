#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
JAVAC_BIN=${JAVAC:-}
JAVA_BIN=${JAVA:-}
if [ -z "$JAVAC_BIN" ]; then JAVAC_BIN=$(command -v javac || true); fi
if [ -z "$JAVA_BIN" ]; then JAVA_BIN=$(command -v java || true); fi
if [ -z "$JAVAC_BIN" ] || [ -z "$JAVA_BIN" ]; then
  echo "Set JAVA_HOME or JAVAC/JAVA to a local JDK 17+ installation." >&2
  exit 2
fi

OUTPUT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/before-i-leave-reminder.XXXXXX")
trap 'rm -rf "$OUTPUT_DIR"' EXIT HUP INT TERM
"$JAVAC_BIN" -d "$OUTPUT_DIR" \
  "$ROOT_DIR/android/app/src/main/java/dev/giann/before_i_leave/ReminderTimeCalculator.java" \
  "$ROOT_DIR/android/app/src/main/java/dev/giann/before_i_leave/ReminderReschedulePolicy.java" \
  "$ROOT_DIR/android/qa/ReminderTimeCalculatorCheck.java"
"$JAVA_BIN" -cp "$OUTPUT_DIR" dev.giann.before_i_leave.ReminderTimeCalculatorCheck
