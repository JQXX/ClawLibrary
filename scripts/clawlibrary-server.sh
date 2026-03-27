#!/bin/bash
set -euo pipefail

ROOT_DIR="/Users/jmini/.openclaw/workspace/ClawLibrary"
PID_FILE="$ROOT_DIR/.clawlibrary-dev.pid"
LOG_DIR="$ROOT_DIR/logs"
OUT_LOG="$LOG_DIR/clawlibrary-dev.out.log"
ERR_LOG="$LOG_DIR/clawlibrary-dev.err.log"
PORT=5173
HOST="0.0.0.0"

mkdir -p "$LOG_DIR"

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

start() {
  if is_running; then
    echo "ClawLibrary dev server already running (PID $(cat "$PID_FILE"))"
    return 0
  fi

  cd "$ROOT_DIR"
  nohup npm run dev -- --host "$HOST" --port "$PORT" >>"$OUT_LOG" 2>>"$ERR_LOG" &
  local pid=$!
  echo "$pid" > "$PID_FILE"
  sleep 2

  if kill -0 "$pid" 2>/dev/null; then
    echo "ClawLibrary dev server started (PID $pid)"
    echo "Logs: $OUT_LOG / $ERR_LOG"
  else
    echo "Failed to start ClawLibrary dev server"
    rm -f "$PID_FILE"
    return 1
  fi
}

stop() {
  if ! is_running; then
    echo "ClawLibrary dev server is not running"
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
  echo "ClawLibrary dev server stopped"
}

status() {
  if is_running; then
    echo "running pid=$(cat "$PID_FILE") url=http://100.83.211.12:$PORT/"
  else
    echo "stopped"
    return 1
  fi
}

logs() {
  tail -n 80 "$OUT_LOG" "$ERR_LOG" 2>/dev/null || true
}

case "${1:-}" in
  start) start ;;
  stop) stop ;;
  restart) stop || true; start ;;
  status) status ;;
  logs) logs ;;
  *)
    echo "Usage: $0 {start|stop|restart|status|logs}"
    exit 1
    ;;
esac
