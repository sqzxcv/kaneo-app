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
# A command that hangs must not hold the queue for everyone. Once the queue is ours, the simulators
# and the command share one time limit. Past it, the command's process group is killed, with its
# children, simulators started here are shut down, and the script exits with 124. Time spent waiting
# in line does not count. The command's stdin is empty, because it runs in a group of its own.
#
#   KANEO_DEVICE_LOCK     Lock file, defaults to ~/.cache/kaneo-app/device.lock
#   KANEO_DEVICE_TIMEOUT  Time limit in seconds, defaults to 1200 (20 minutes)
set -euo pipefail

if [[ $# -eq 0 ]]; then
  sed -n '2,18p' "$0" >&2
  exit 2
fi

timeout_seconds="${KANEO_DEVICE_TIMEOUT:-1200}"
if [[ ! "$timeout_seconds" =~ ^[1-9][0-9]*$ ]]; then
  echo "with_device: KANEO_DEVICE_TIMEOUT must be a number of seconds, got: $timeout_seconds" >&2
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
  job=""
  deadline=$((SECONDS + timeout_seconds))

  # Stops the running job's process group, and nothing outside it: politely, then for good.
  stop_job() {
    [[ -n "$job" ]] || return 0
    kill -TERM -- "-$job" 2>/dev/null || true
    local tries=0
    while kill -0 -- "-$job" 2>/dev/null && ((tries < 25)); do
      sleep 0.2
      tries=$((tries + 1))
    done
    kill -KILL -- "-$job" 2>/dev/null || true
    wait "$job" 2>/dev/null || true
    job=""
  }

  # Runs a command in a process group of its own. Returns its exit code, or 124 once the deadline
  # has passed and the group is gone. `set -m` is what gives a background job its own group.
  run_until_deadline() {
    set -m
    "$@" </dev/null &
    job=$!
    set +m
    while kill -0 "$job" 2>/dev/null; do
      if ((SECONDS >= deadline)); then
        stop_job
        return 124
      fi
      sleep 0.2
    done
    local status=0
    wait "$job" 2>/dev/null || status=$?
    job=""
    return "$status"
  }

  cleanup() {
    stop_job
    # A simulator stuck shutting down must not hold the queue either.
    deadline=$((SECONDS + 60))
    local udid
    for udid in ${started[@]+"${started[@]}"}; do
      echo "with_device: shutting down simulator $udid" >&2
      run_until_deadline xcrun simctl shutdown "$udid" || true
    done
    rm -f "$lock_file.holder"
  }
  trap cleanup EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM

  timed_out() {
    echo "with_device: timed out after $timeout_seconds seconds and killed: $*" >&2
    echo "with_device: the device queue is free again. KANEO_DEVICE_TIMEOUT sets a longer limit." >&2
    exit 124
  }

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
      status=0
      run_until_deadline xcrun simctl bootstatus "$udid" -b >/dev/null || status=$?
      if ((status == 124)); then
        timed_out "xcrun simctl bootstatus $udid"
      elif ((status != 0)); then
        exit "$status"
      fi
    fi
    shift 2
  done

  status=0
  run_until_deadline "$@" || status=$?
  if ((status == 124 && SECONDS >= deadline)); then
    timed_out "$*"
  fi
  exit "$status"
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
