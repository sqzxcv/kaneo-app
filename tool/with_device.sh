#!/usr/bin/env bash
# Runs one command while holding the machine-wide device queue, so that only one simulator run or
# full build happens at a time. Other callers wait in line until the command finishes.
#
#   tool/with_device.sh flutter build macos
#   tool/with_device.sh --boot "iPhone 17" flutter test integration_test -d "iPhone 17"
#
# --boot starts a simulator, without opening Simulator.app, once the queue is ours. It can be
# repeated. Only simulators started this way are shut down afterwards: any other simulator belongs
# to someone else and is left alone, even one that came up while the command ran. The lock is held
# by the kernel, so it is released even if the holder crashes.
#
#   KANEO_DEVICE_LOCK  Lock file, defaults to ~/.cache/kaneo-app/device.lock
set -euo pipefail

if [[ $# -eq 0 ]]; then
  sed -n '2,12p' "$0" >&2
  exit 2
fi

lock_file="${KANEO_DEVICE_LOCK:-$HOME/.cache/kaneo-app/device.lock}"
mkdir -p "$(dirname "$lock_file")"

# Accepts a simulator's exact name or its UDID.
simulator_udid() {
  if [[ "$1" =~ ^[0-9A-F-]{36}$ ]]; then
    echo "$1"
    return 0
  fi
  xcrun simctl list devices available | grep -F -- "    $1 (" |
    sed -nE 's/.*\(([0-9A-F-]{36})\).*/\1/p' | tail -n 1
}

# Runs inside the lock.
if [[ "${KANEO_DEVICE_LOCK_HELD:-}" == "$lock_file" ]]; then
  echo "pid $PPID: $*" >"$lock_file.holder"
  started=()
  cleanup() {
    local udid
    for udid in ${started[@]+"${started[@]}"}; do
      echo "with_device: shutting down simulator $udid" >&2
      xcrun simctl shutdown "$udid" || true
    done
    rm -f "$lock_file.holder"
  }
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  while [[ "${1:-}" == "--boot" ]]; do
    udid="$(simulator_udid "$2")"
    if [[ -z "$udid" ]]; then
      echo "with_device: no simulator named $2" >&2
      exit 1
    fi
    if xcrun simctl list devices booted | grep -qF "$udid"; then
      echo "with_device: simulator $udid was already running, leaving it running afterwards" >&2
    else
      started+=("$udid")
      xcrun simctl bootstatus "$udid" -b >/dev/null
    fi
    shift 2
  done

  "$@"
  exit $?
fi

export KANEO_DEVICE_LOCK_HELD="$lock_file"

run_locked() {
  # `lockf` on macOS, `flock` on Linux. Both wait, and both use a lock the kernel releases on exit.
  # -k keeps the file: removing it would let a later caller lock a new file next to a waiting one.
  if command -v lockf >/dev/null; then
    lockf -k "$@"
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
