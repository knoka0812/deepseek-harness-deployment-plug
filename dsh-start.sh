#!/usr/bin/env bash
set -euo pipefail

APP_DIR=/data/deepseek-harness
RUNTIME_DIR=/data/deepseek-harness-runtime
ENV_DIR=/data/miniconda/envs/deepseek-harness
PATCH_FILE="$RUNTIME_DIR/cordis.yml"
PID_FILE="$RUNTIME_DIR/dsh.pid"
LOG_FILE="$RUNTIME_DIR/dsh.log"

# 浏览器实际访问的 authority（公网域名:端口），不要带协议或路径。
PUBLIC_AUTHORITY='juxm92p7nh764gamakea100.funhpc.com:30499'

mkdir -p "$RUNTIME_DIR/home"

if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "DeepSeek Harness is already running (PID $(cat "$PID_FILE"))."
  exit 0
fi

export PATH="$ENV_DIR/bin:$PATH"
export HOME="$RUNTIME_DIR/home"
export XDG_CACHE_HOME="$RUNTIME_DIR/cache"
export XDG_CONFIG_HOME="$RUNTIME_DIR/config"
export XDG_DATA_HOME="$RUNTIME_DIR/data"

cd /data
nohup node "$APP_DIR/apps/cli/lib/bin.js" web \
  --patch "$PATCH_FILE" \
  --trusted-host "$PUBLIC_AUTHORITY" \
  >>"$LOG_FILE" 2>&1 &

pid=$!
echo "$pid" >"$PID_FILE"

for _ in {1..30}; do
  if ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$PID_FILE"
    echo "DeepSeek Harness failed to start. See $LOG_FILE." >&2
    exit 1
  fi

  if curl --silent --fail --output /dev/null http://127.0.0.1:7086/; then
    echo "DeepSeek Harness started on http://0.0.0.0:7086 (PID $pid)."
    exit 0
  fi

  sleep 1
done

echo "DeepSeek Harness did not become ready in 30 seconds. See $LOG_FILE." >&2
exit 1
