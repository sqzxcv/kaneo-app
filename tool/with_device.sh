#!/usr/bin/env bash
# Runs one command while holding the machine-wide device queue, so that only one simulator run or
# full build happens at a time. Other callers wait in line until the command finishes.
#
#   tool/with_device.sh flutter build macos
#   tool/with_device.sh flutter test integration_test -d "iPhone 17"
#
# Simulators booted while the command runs are shut down afterwards. Simulators that were already
# running belong to someone else and are left alone. The lock is held by the kernel, so it is
# released even if the holder crashes.
#
#   KANEO_DEVICE_LOCK  Lock file, defaults to ~/.cache/kaneo-app/device.lock
set -euo pipefail

if [[ $# -eq 0 ]]; then
  sed -n '2,12p' "$0" >&2
  exit 2
fi

lock_file="${KANEO_DEVICE_LOCK:-$HOME/.cache/kaneo-app/device.lock}"
mkdir -p "$(dirname "$lock_file")"

booted_simulators() {
  command -v xcrun >/dev/null || return 0
  xcrun simctl list devices booted 2>/dev/null |
    sed -nE 's/.*\(([0-9A-F-]{36})\) \(Booted\).*/\1/p' | sort
}

# Runs inside the lock.
if [[ "${KANEO_DEVICE_LOCK_HELD:-}" == "$lock_file" ]]; then
  echo "pid $PPID: $*" >"$lock_file.holder"
  before="$(booted_simulators)"
  cleanup() {
    local udid
    for udid in $(comm -13 <(echo "$before") <(booted_simulators)); do
      echo "with_device: shutting down simulator $udid" >&2
      xcrun simctl shutdown "$udid" || true
    done
    rm -f "$lock_file.holder"
  }
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  "$@"
  exit $?
fi

export KANEO_DEVICE_LOCK_HELD="$lock_file"

run_locked() {
  # `lockf` on macOS, `flock` on Linux. Both wait, and both use a lock the kernel releases on exit.
  if command -v lockf >/dev/null; then
    lockf "$@"
  elif command -v flock >/dev/null; then
    local file="$1"
    shift
    flock "$file" "$@"
  else
    echo "with_device: neither lockf nor flock is available" >&2
    exit 1
  fi
}

if [[ -s "$lock_file.holder" ]]; then
  echo "with_device: waiting for the device queue, held by $(cat "$lock_file.holder")" >&2
fi
run_locked "$lock_file" "$0" "$@"
