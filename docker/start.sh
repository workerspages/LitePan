#!/bin/sh
# LitePan + OpenList 一体化启动脚本（单容器、零 Volume 部署）
#
# OpenList 以 sidecar 跑在 127.0.0.1:$OPENLIST_PORT（默认 5244），仅供本机 LitePan 连接，
# 不对外暴露公网访问。LitePan 通过自带的 OpenList 驱动（服务器填 http://127.0.0.1:5244）使用它。
set -eu

if [ "${OPENLIST_ENABLED:-true}" != "true" ]; then
  echo "[start.sh] OPENLIST_ENABLED=false，跳过 OpenList，直接启动 LitePan"
  exec /app/litepan
fi

OL_DATA="${OPENLIST_DATA_DIR:-/app/openlist-data}"
OL_PORT="${OPENLIST_PORT:-5244}"
mkdir -p "$OL_DATA" /app/data/log

# ---- OpenList 数据库：优先复用 LitePan 的 MySQL，实现零 Volume ----
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

# 每次启动重写 config.json，保证环境变量始终生效；只监听本机，不暴露公网
cat > "$OL_DATA/config.json" <<EOF
{
  "scheme": {
    "address": "127.0.0.1",
    "http_port": $OL_PORT
  },
  "database": $DB_JSON
}
EOF

# 管理员密码每次启动同步为环境变量值（默认 openlist，务必修改）
if ! /app/openlist --data "$OL_DATA" admin set "${OPENLIST_ADMIN_PASSWORD:-openlist}" > /dev/null 2>&1; then
  echo "[start.sh] WARN: openlist admin 密码设置失败，详见日志"
fi

/app/openlist --data "$OL_DATA" server >> /app/data/log/openlist.log 2>&1 &
echo "[start.sh] OpenList sidecar 已启动（127.0.0.1:$OL_PORT，仅本机），日志：/app/data/log/openlist.log"

exec /app/litepan
