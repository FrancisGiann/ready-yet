#!/usr/bin/env sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
OUT=$(mktemp -d "${TMPDIR:-/tmp}/ready-yet-schedule.XXXXXX")
trap 'rm -rf "$OUT"' EXIT HUP INT TERM
"${JAVAC:-javac}" -d "$OUT" "$ROOT/android/app/src/main/java/dev/giann/before_i_leave/ScheduleTimePolicy.java" "$ROOT/android/app/src/main/java/dev/giann/before_i_leave/ScheduleActionPolicy.java" "$ROOT/android/qa/ScheduleTimePolicyCheck.java"
"${JAVA:-java}" -cp "$OUT" ScheduleTimePolicyCheck
