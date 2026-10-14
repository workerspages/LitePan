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
# 注意：OpenList 环境变量默认带 OPENLIST_ 前缀
OL_DB_DSN="${OPENLIST_DB_DSN:-}"
if [ -z "$OL_DB_DSN" ] && [ "${LITEPAN_DB_DRIVER:-sqlite}" = "mysql" ] && [ -n "${LITEPAN_DB_DSN:-}" ]; then
  OL_DB_DSN="$LITEPAN_DB_DSN"
fi

if [ -n "$OL_DB_DSN" ]; then
  export OPENLIST_DB_TYPE=mysql
  export OPENLIST_DB_DSN="$OL_DB_DSN"
  export OPENLIST_DB_TABLE_PREFIX=openlist_
  echo "[start.sh] OpenList 数据库：mysql（与 LitePan 共用，表前缀 openlist_）"
  # 诊断：确认传给 OpenList 的 DSN 结构（密码脱敏）
  _masked="$(printf '%s' "$OL_DB_DSN" | sed -E 's/^([^:]+):[^@]*@/\1:***@/')"
  echo "[start.sh] DSN 诊断：长度=${#OL_DB_DSN}，结构=${_masked}"
  case "$OL_DB_DSN" in */*) echo "[start.sh] DSN 诊断：含斜杠";; *) echo "[start.sh] DSN 诊断：!!! 不含斜杠 !!!";; esac
else
  echo "[start.sh] WARN: 未配置 MySQL，OpenList 使用容器内 sqlite，重部署后网盘配置会丢失"
fi

# config.json 只负责监听配置（数据库走上面的环境变量，避免 DSN 特殊字符破坏 JSON）
# 每次启动重写，保证环境变量始终生效；只监听本机，不暴露公网
cat > "$OL_DATA/config.json" <<EOF
{
  "scheme": {
    "address": "127.0.0.1",
    "http_port": $OL_PORT
  }
}
EOF

# 管理员密码每次启动同步为环境变量值（默认 openlist，务必修改）
if ! /app/openlist --data "$OL_DATA" --log-std admin set "${OPENLIST_ADMIN_PASSWORD:-openlist}" >> /app/data/log/openlist.log 2>&1; then
  echo "[start.sh] WARN: openlist admin 密码设置失败，详见 /app/data/log/openlist.log"
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
