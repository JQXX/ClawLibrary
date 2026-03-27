#!/bin/bash
set -euo pipefail

ROOT_DIR="/Users/jmini/.openclaw/workspace/ClawLibrary"
LOG_DIR="$ROOT_DIR/logs"
mkdir -p "$LOG_DIR"

MODE="${CLAWLIBRARY_MODE:-stable}"
if [[ $# -ge 1 && ( "$1" == "stable" || "$1" == "dev" ) ]]; then
  MODE="$1"
  shift
fi
ACTION="${1:-status}"

case "$MODE" in
  stable)
    PID_FILE="$ROOT_DIR/.clawlibrary-stable.pid"
    OUT_LOG="$LOG_DIR/clawlibrary-stable.out.log"
    ERR_LOG="$LOG_DIR/clawlibrary-stable.err.log"
    PORT=5173
    START_CMD=(npm run preview -- --host 0.0.0.0 --port "$PORT")
    PRE_START_CMD=(npm run build)
    ;;
  dev)
    PID_FILE="$ROOT_DIR/.clawlibrary-dev.pid"
    OUT_LOG="$LOG_DIR/clawlibrary-dev.out.log"
    ERR_LOG="$LOG_DIR/clawlibrary-dev.err.log"
    PORT=5174
    START_CMD=(npm run dev -- --host 0.0.0.0 --port "$PORT")
    PRE_START_CMD=()
    ;;
  *)
    echo "Unknown mode: $MODE"
    echo "Usage: $0 [stable|dev] {start|stop|restart|status|logs|doctor}"
    exit 1
    ;;
esac

is_running() {
  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid=$(cat "$PID_FILE" 2>/dev/null || true)
    if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

check_http() {
  python3 - <<PY
import urllib.request
url = 'http://127.0.0.1:${PORT}/'
try:
    with urllib.request.urlopen(url, timeout=3) as r:
        print(f'http ok status={r.status} url={url}')
except Exception as e:
    print(f'http fail url={url} error={e!r}')
PY
}

explain_failure() {
  echo "ClawLibrary $MODE server failed to start."
  if [[ "$MODE" == "stable" ]]; then
    echo "Likely causes:"
    echo "- build failed (TypeScript / Vite error)"
    echo "- preview process crashed immediately"
    echo "- port $PORT is already occupied"
  else
    echo "Likely causes:"
    echo "- vite dev process crashed immediately"
    echo "- port $PORT is already occupied"
  fi
  echo "Check logs: $OUT_LOG and $ERR_LOG"
  echo "Quick doctor: ./scripts/clawlibrary-server.sh $MODE doctor"
}

start() {
  if is_running; then
    echo "ClawLibrary $MODE server already running (PID $(cat "$PID_FILE"))"
    check_http || true
    return 0
  fi

  cd "$ROOT_DIR"
  : > "$OUT_LOG"
  : > "$ERR_LOG"

  if [[ ${#PRE_START_CMD[@]} -gt 0 ]]; then
    echo "Building before starting $MODE server..."
    if ! "${PRE_START_CMD[@]}" 2>&1 | tee -a "$OUT_LOG"; then
      explain_failure
      return 1
    fi
  fi

  nohup "${START_CMD[@]}" >>"$OUT_LOG" 2>>"$ERR_LOG" &
  local pid=$!
  echo "$pid" > "$PID_FILE"
  sleep 2

  if kill -0 "$pid" 2>/dev/null; then
    echo "ClawLibrary $MODE server started (PID $pid)"
    echo "URL: http://100.83.211.12:$PORT/"
    echo "Logs: $OUT_LOG / $ERR_LOG"
    check_http || true
  else
    rm -f "$PID_FILE"
    explain_failure
    return 1
  fi
}

stop() {
  if ! is_running; then
    echo "ClawLibrary $MODE server is not running"
    rm -f "$PID_FILE"
    return 0
  fi

  local pid
  pid=$(cat "$PID_FILE")
  kill "$pid" 2>/dev/null || true
  sleep 1
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
  echo "ClawLibrary $MODE server stopped"
}

status() {
  if is_running; then
    echo "running mode=$MODE pid=$(cat "$PID_FILE") url=http://100.83.211.12:$PORT/"
    check_http || true
  else
    echo "stopped mode=$MODE"
    return 1
  fi
}

logs() {
  tail -n 120 "$OUT_LOG" "$ERR_LOG" 2>/dev/null || true
}

doctor() {
  echo "== ClawLibrary doctor: $MODE =="
  echo "root=$ROOT_DIR"
  echo "pid_file=$PID_FILE"
  echo "port=$PORT"
  if is_running; then
    echo "process=running pid=$(cat "$PID_FILE")"
  else
    echo "process=stopped"
  fi
  check_http || true
  echo "--- last logs ---"
  tail -n 60 "$OUT_LOG" "$ERR_LOG" 2>/dev/null || true
}

case "$ACTION" in
  start) start ;;
  stop) stop ;;
  restart) stop || true; start ;;
  status) status ;;
  logs) logs ;;
  doctor) doctor ;;
  *)
    echo "Usage: $0 [stable|dev] {start|stop|restart|status|logs|doctor}"
    exit 1
    ;;
esac
