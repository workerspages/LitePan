#!/bin/sh
# LitePan + OpenList 一体化启动脚本（单容器、零 Volume 部署）
#
# 正常模式：OpenList 以 sidecar 跑在 127.0.0.1:$OPENLIST_PORT（默认 5244），仅供本机
#   LitePan 连接，不对外暴露。LitePan 通过自带的 OpenList 驱动使用它。
# SETUP 模式（OPENLIST_SETUP_MODE=true）：只启动 OpenList，监听 0.0.0.0:$PORT，
#   通过 Railway 公网地址打开 OpenList 管理界面添加网盘。配完后改回 false 重部署。
set -eu

OL_DATA="${OPENLIST_DATA_DIR:-/app/openlist-data}"
OL_PORT="${OPENLIST_PORT:-5244}"
mkdir -p "$OL_DATA" /app/data/log

# ---- OpenList 数据库：优先复用 LitePan 的 MySQL，实现零 Volume ----
# 注意：OpenList 环境变量默认带 OPENLIST_ 前缀
OL_DB_DSN="${OPENLIST_DB_DSN:-}"
# 基本合法性校验：DSN 至少形如 user:pass@tcp(host:port)/dbname；误填则忽略
case "$OL_DB_DSN" in
  *@*/*) ;;
  "") ;;
  *) echo "[start.sh] WARN: OPENLIST_DB_DSN 的值不像合法 DSN（长度=${#OL_DB_DSN}），已忽略"; OL_DB_DSN="" ;;
esac
if [ -z "$OL_DB_DSN" ] && [ "${LITEPAN_DB_DRIVER:-sqlite}" = "mysql" ] && [ -n "${LITEPAN_DB_DSN:-}" ]; then
  OL_DB_DSN="$LITEPAN_DB_DSN"
fi

if [ -n "$OL_DB_DSN" ]; then
  export OPENLIST_DB_TYPE=mysql
  export OPENLIST_DB_DSN="$OL_DB_DSN"
  export OPENLIST_DB_TABLE_PREFIX=openlist_
  echo "[start.sh] OpenList 数据库：mysql（与 LitePan 共用，表前缀 openlist_）"
else
  echo "[start.sh] WARN: 未配置 MySQL，OpenList 使用容器内 sqlite；注意重部署后数据会丢失"
fi

SETUP_MODE="${OPENLIST_SETUP_MODE:-false}"
if [ "$SETUP_MODE" = "true" ]; then
  LISTEN_ADDR="0.0.0.0"
  LISTEN_PORT="${PORT:-8080}"
else
  LISTEN_ADDR="127.0.0.1"
  LISTEN_PORT="$OL_PORT"
fi

# 每次启动重写 config.json，保证配置始终生效
cat > "$OL_DATA/config.json" <<EOF
{
  "scheme": {
    "address": "$LISTEN_ADDR",
    "http_port": $LISTEN_PORT
  }
}
EOF

# 管理员密码每次启动同步为环境变量值（默认 openlist，务必修改）
if ! /app/openlist --data "$OL_DATA" --log-std admin set "${OPENLIST_ADMIN_PASSWORD:-openlist}" >> /app/data/log/openlist.log 2>&1; then
  echo "[start.sh] WARN: openlist admin 密码设置失败，详见 /app/data/log/openlist.log"
fi

if [ "$SETUP_MODE" = "true" ]; then
  echo "[start.sh] SETUP 模式：仅启动 OpenList（$LISTEN_ADDR:$LISTEN_PORT）"
  echo "[start.sh] 用 Railway 公网地址打开 OpenList（admin / 你的密码）添加网盘；完成后设回 false 重部署"
  echo "[start.sh] 注意：sqlite 下重部署会丢失配置，建议先配好 MySQL 再进 SETUP 模式"
  exec /app/openlist --data "$OL_DATA" --log-std server
fi

if [ "${OPENLIST_ENABLED:-true}" != "true" ]; then
  echo "[start.sh] OPENLIST_ENABLED=false，跳过 OpenList，直接启动 LitePan"
  exec /app/litepan
fi

/app/openlist --data "$OL_DATA" --log-std server >> /app/data/log/openlist.log 2>&1 &
echo "[start.sh] 等待 OpenList 就绪（127.0.0.1:$OL_PORT）…"

# 等待端口就绪（最多 60 秒）；超时则把日志尾部打到 stdout，方便在 Railway 日志里直接看到真实错误
OK=0
for i in $(seq 1 60); do
  if curl -s -o /dev/null --max-time 2 "http://127.0.0.1:$OL_PORT/"; then
    OK=1
    break
  fi
  sleep 1
done

if [ "$OK" = "1" ]; then
  echo "[start.sh] OpenList sidecar 就绪（127.0.0.1:$OL_PORT，仅本机）"
else
  echo "[start.sh] ERROR: OpenList 60 秒内未就绪，以下是它的日志尾部："
  tail -n 60 /app/data/log/openlist.log || true
  echo "[start.sh] WARN: 继续启动 LitePan（OpenList 不可用）"
fi

exec /app/litepan
