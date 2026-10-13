#!/bin/sh
# LitePan + OpenList 一体化启动脚本（单容器、零 Volume 部署）
#
# 正常模式：
#   OpenList 以 sidecar 跑在 127.0.0.1:$OPENLIST_PORT（默认 5244，仅本机可达），
#   LitePan 跑在 $LITEPAN_LISTEN（默认 :8080），通过自带 OpenList 驱动连接它。
# SETUP 模式（OPENLIST_SETUP_MODE=true）：
#   只启动 OpenList 并监听 $PORT（公网可达），用于首次在 OpenList 管理界面添加网盘。
#   配完后改回 false 重部署即可。
#
# OpenList 的数据库默认复用 LitePan 的 MySQL（LITEPAN_DB_DSN），表名前缀 openlist_，
# 因此网盘配置在重部署后依然保留，可用 OPENLIST_DB_DSN 覆盖。
set -eu

OL_DATA="${OPENLIST_DATA_DIR:-/app/openlist-data}"
OL_PORT="${OPENLIST_PORT:-5244}"
mkdir -p "$OL_DATA" /app/data/log

# ---- OpenList 数据库 ----
OL_DB_DSN="${OPENLIST_DB_DSN:-}"
if [ -z "$OL_DB_DSN" ] && [ "${LITEPAN_DB_DRIVER:-sqlite}" = "mysql" ] && [ -n "${LITEPAN_DB_DSN:-}" ]; then
  OL_DB_DSN="$LITEPAN_DB_DSN"
fi

if [ -n "$OL_DB_DSN" ]; then
  # 注意：DSN 里如含双引号或反斜杠需自行转义，常规密码不受影响
  DB_JSON="{\"type\": \"mysql\", \"dsn\": \"$OL_DB_DSN\", \"table_prefix\": \"openlist_\"}"
else
  # 回退到容器内 sqlite：能跑，但重部署后网盘配置会丢失，仅作临时方案
  DB_JSON="{\"type\": \"sqlite3\", \"db_file\": \"$OL_DATA/data.db\"}"
  echo "[start.sh] WARN: 未配置 MySQL，OpenList 使用容器内 sqlite，重部署后网盘配置会丢失"
fi

if [ "${OPENLIST_SETUP_MODE:-false}" = "true" ]; then
  LISTEN_ADDR="0.0.0.0"
  LISTEN_PORT="${PORT:-8080}"
  MODE="setup"
else
  LISTEN_ADDR="127.0.0.1"
  LISTEN_PORT="$OL_PORT"
  MODE="sidecar"
fi

# 每次启动重写 config.json，保证环境变量始终生效
cat > "$OL_DATA/config.json" <<EOF
{
  "scheme": {
    "address": "$LISTEN_ADDR",
    "http_port": $LISTEN_PORT
  },
  "database": $DB_JSON
}
EOF

# 管理员密码每次启动同步为环境变量值（默认 openlist，务必修改）
if ! /app/openlist --data "$OL_DATA" admin set "${OPENLIST_ADMIN_PASSWORD:-openlist}" > /dev/null 2>&1; then
  echo "[start.sh] WARN: openlist admin 密码设置失败，详见日志"
fi

if [ "$MODE" = "setup" ]; then
  echo "[start.sh] SETUP 模式：仅启动 OpenList（$LISTEN_ADDR:$LISTEN_PORT）"
  echo "[start.sh] 请用公网地址打开 OpenList（admin / 你的密码）添加网盘，完成后关闭 SETUP 模式重部署"
  exec /app/openlist --data "$OL_DATA" server
fi

if [ "${OPENLIST_ENABLED:-true}" = "true" ]; then
  /app/openlist --data "$OL_DATA" server >> /app/data/log/openlist.log 2>&1 &
  echo "[start.sh] OpenList sidecar 已启动（127.0.0.1:$OL_PORT），日志：/app/data/log/openlist.log"
else
  echo "[start.sh] OPENLIST_ENABLED=false，跳过 OpenList"
fi

exec /app/litepan
