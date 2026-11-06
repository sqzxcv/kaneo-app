#!/usr/bin/env bash
# Runs a private Kaneo API on this machine: Homebrew Postgres plus the API process only, without
# the web app and docs site. Every worktree shares one instance and one source checkout.
#
#   tool/local_kaneo.sh setup    Install the source, dependencies and database, then write config
#   tool/local_kaneo.sh start    Start Postgres and the API, and wait until the API is healthy
#   tool/local_kaneo.sh seed     Create the dev account, API key and sample data, then write dev.env
#   tool/local_kaneo.sh stop     Stop the API and Postgres started by this script
#   tool/local_kaneo.sh status   Show what is running
#
# Files outside the repository:
#   ~/.config/kaneo-app/api.env  API settings (database address, auth secret)
#   ~/.config/kaneo-app/dev.env  App settings, passed to Flutter with --dart-define-from-file
#   ~/.local/share/kaneo-app/    Kaneo source, Postgres data, logs and pid files
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$HOME/.config/kaneo-app"
DATA_DIR="$HOME/.local/share/kaneo-app"
SRC_DIR="$DATA_DIR/kaneo"
PG_DATA="$DATA_DIR/pgdata"
API_ENV="$CONFIG_DIR/api.env"
API_PID="$DATA_DIR/api.pid"
API_LOG="$DATA_DIR/api.log"
PG_LOG="$DATA_DIR/postgres.log"

PG_PORT="${KANEO_PG_PORT:-55432}"
API_PORT="${KANEO_API_PORT:-1337}"
KANEO_REMOTE="https://github.com/sqzxcv/kaneo.git"

PG_BIN="$(brew --prefix postgresql@17 2>/dev/null)/bin"
NODE_BIN="$(brew --prefix node@24 2>/dev/null)/bin"

die() {
  echo "local_kaneo: $*" >&2
  exit 1
}

require_tools() {
  [[ -x "$PG_BIN/pg_ctl" ]] || die "Postgres is missing. Run: brew install postgresql@17"
  [[ -x "$NODE_BIN/node" ]] || die "Node 24 is missing. Run: brew install node@24"
  command -v pnpm >/dev/null || die "pnpm is missing. Run: brew install pnpm"
}

pinned_commit() {
  git -C "$REPO_ROOT" ls-tree HEAD kaneo | awk '{print $3}'
}

install_source() {
  local commit current
  commit="$(pinned_commit)"
  [[ -n "$commit" ]] || die "Cannot read the kaneo submodule commit."
  if [[ ! -d "$SRC_DIR/.git" ]]; then
    git init -q "$SRC_DIR"
    git -C "$SRC_DIR" remote add origin "$KANEO_REMOTE"
  fi
  current="$(git -C "$SRC_DIR" rev-parse -q --verify HEAD || true)"
  if [[ "$current" != "$commit" ]]; then
    git -C "$SRC_DIR" fetch -q --depth 1 origin "$commit"
    git -C "$SRC_DIR" checkout -q --force FETCH_HEAD
  fi
  (
    cd "$SRC_DIR"
    export PATH="$NODE_BIN:$PATH" HUSKY=0 CI=1
    pnpm install --frozen-lockfile --filter "@kaneo/api..." --filter "kaneo"
    pnpm --filter "@kaneo/api^..." run build
  )
}

pg_running() {
  "$PG_BIN/pg_ctl" -D "$PG_DATA" status >/dev/null 2>&1
}

start_postgres() {
  pg_running && return 0
  "$PG_BIN/pg_ctl" -D "$PG_DATA" -l "$PG_LOG" -w -o "-p $PG_PORT -c listen_addresses=localhost" start >/dev/null
}

setup_database() {
  if [[ ! -f "$PG_DATA/PG_VERSION" ]]; then
    "$PG_BIN/initdb" -D "$PG_DATA" -U kaneo --auth=trust --encoding=UTF8 --locale=en_US.UTF-8 >/dev/null
  fi
  start_postgres
  if ! "$PG_BIN/psql" -h localhost -p "$PG_PORT" -U kaneo -d postgres -tAc \
    "SELECT 1 FROM pg_database WHERE datname = 'kaneo'" | grep -q 1; then
    "$PG_BIN/createdb" -h localhost -p "$PG_PORT" -U kaneo kaneo
  fi
}

write_api_env() {
  [[ -f "$API_ENV" ]] && return 0
  (
    umask 077
    cat >"$API_ENV" <<EOF
KANEO_CLIENT_URL=http://localhost:5173
KANEO_API_URL=http://localhost:$API_PORT
DATABASE_URL=postgresql://kaneo@localhost:$PG_PORT/kaneo
AUTH_SECRET=$(openssl rand -hex 32)
EOF
  )
}

api_running() {
  [[ -f "$API_PID" ]] && kill -0 "$(cat "$API_PID")" 2>/dev/null
}

wait_for_api() {
  local _
  for _ in $(seq 1 120); do
    if curl --silent --fail --max-time 2 "http://localhost:$API_PORT/api/health" >/dev/null; then
      return 0
    fi
    api_running || die "The API exited during startup. See $API_LOG"
    sleep 1
  done
  die "The API did not become healthy in 120 seconds. See $API_LOG"
}

start_api() {
  if api_running; then
    echo "API already running (pid $(cat "$API_PID"))."
    return 0
  fi
  (
    cd "$SRC_DIR/apps/api"
    set -a
    # shellcheck disable=SC1090
    source "$API_ENV"
    set +a
    export PATH="$NODE_BIN:$PATH"
    export NODE_OPTIONS="--max-old-space-size=512"
    nohup ./node_modules/.bin/tsx src/index.ts >"$API_LOG" 2>&1 &
    echo $! >"$API_PID"
  )
  wait_for_api
}

cmd_setup() {
  require_tools
  mkdir -p "$CONFIG_DIR" "$DATA_DIR"
  chmod 700 "$CONFIG_DIR"
  install_source
  setup_database
  write_api_env
  echo "Setup finished. Next: tool/local_kaneo.sh start && tool/local_kaneo.sh seed"
}

cmd_start() {
  require_tools
  [[ -d "$SRC_DIR/apps/api/node_modules" ]] || die "Run tool/local_kaneo.sh setup first."
  [[ -f "$API_ENV" ]] || die "Run tool/local_kaneo.sh setup first."
  start_postgres
  start_api
  echo "Kaneo API: http://localhost:$API_PORT (log: $API_LOG)"
}

cmd_seed() {
  curl --silent --fail --max-time 2 "http://localhost:$API_PORT/api/health" >/dev/null ||
    die "The API is not running. Run: tool/local_kaneo.sh start"
  (cd "$REPO_ROOT" && dart run tool/seed_local_kaneo.dart "http://localhost:$API_PORT" "$CONFIG_DIR/dev.env")
}

cmd_stop() {
  if api_running; then
    local pid
    pid="$(cat "$API_PID")"
    # tsx runs the server in a child process, so stop the children first.
    pkill -TERM -P "$pid" 2>/dev/null || true
    kill -TERM "$pid" 2>/dev/null || true
    echo "API stopped."
  fi
  rm -f "$API_PID"
  if pg_running; then
    "$PG_BIN/pg_ctl" -D "$PG_DATA" -m fast -w stop >/dev/null
    echo "Postgres stopped."
  fi
}

cmd_status() {
  if api_running; then echo "API: running (pid $(cat "$API_PID"))"; else echo "API: stopped"; fi
  if pg_running; then echo "Postgres: running (port $PG_PORT)"; else echo "Postgres: stopped"; fi
}

case "${1:-}" in
setup) cmd_setup ;;
start) cmd_start ;;
seed) cmd_seed ;;
stop) cmd_stop ;;
status) cmd_status ;;
*)
  sed -n '2,13p' "$0" >&2
  exit 2
  ;;
esac
