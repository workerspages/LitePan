# syntax=docker/dockerfile:1

ARG DEBIAN_IMAGE=debian:bookworm-slim
# OpenList 版本：latest 表示每次构建都用最新 release；也可 pin 死，如 v4.1.6
ARG OPENLIST_VERSION=latest

FROM node:20-bookworm-slim AS web

WORKDIR /src/web

COPY web/package.json web/package-lock.json ./
RUN npm config set registry https://registry.npmmirror.com \
    && npm ci

COPY web/ ./
RUN npm run type-check && npm run build


FROM golang:1.26.6-bookworm AS build

WORKDIR /src

# 与 go.mod 的 go 1.26.4 对齐；local 禁止再去拉 toolchain，避免 proxy.golang.org 中断
ENV GOTOOLCHAIN=local \
    CGO_ENABLED=0 \
    GOPROXY=https://goproxy.cn,direct
ARG BUILD_TAGS=fuse

COPY go.mod go.sum ./
RUN go mod download

COPY . .
COPY --from=web /src/internal/api/web /src/internal/api/web

RUN go build -tags "${BUILD_TAGS}" -trimpath -ldflags="-s -w" -o /out/litepan ./cmd/litepan


# ---- OpenList 二进制（sidecar）：与 LitePan 跑在同一容器，单部署即得全部 ----
FROM ${DEBIAN_IMAGE} AS openlist
ARG OPENLIST_VERSION
ARG TARGETARCH
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /opt/openlist \
    && OL_ARCH="${TARGETARCH:-amd64}" \
    && if [ "$OL_ARCH" != "amd64" ] && [ "$OL_ARCH" != "arm64" ]; then echo "unsupported arch: $OL_ARCH" >&2; exit 1; fi \
    && if [ "$OPENLIST_VERSION" = "latest" ]; then \
         OL_URL="https://github.com/OpenListTeam/OpenList/releases/latest/download/openlist-linux-${OL_ARCH}.tar.gz"; \
       else \
         OL_URL="https://github.com/OpenListTeam/OpenList/releases/download/${OPENLIST_VERSION}/openlist-linux-${OL_ARCH}.tar.gz"; \
       fi \
    && echo "downloading $OL_URL" \
    && curl -fsSL "$OL_URL" -o /tmp/openlist.tgz \
    && tar -xzf /tmp/openlist.tgz -C /opt/openlist \
    && rm -f /tmp/openlist.tgz \
    && chmod +x /opt/openlist/openlist \
    && /opt/openlist/openlist version


FROM ${DEBIAN_IMAGE} AS runtime

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl tzdata fuse3 \
    && sed -i 's/^#user_allow_other/user_allow_other/' /etc/fuse.conf 2>/dev/null || true \
    && grep -q '^user_allow_other' /etc/fuse.conf || echo user_allow_other >> /etc/fuse.conf \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mkdir -p /app/data/log /app/strm /app/mounts /app/lp-bridge-data

COPY --from=build /out/litepan /app/litepan
COPY --from=openlist /opt/openlist/openlist /app/lp-bridge
COPY docker/start.sh /app/start.sh
RUN chmod +x /app/start.sh /app/lp-bridge

ENV LITEPAN_DATA_DIR=/app/data \
    LITEPAN_STRM_DIR=/app/strm \
    LITEPAN_LISTEN=:8080 \
    LITEPAN_LOG_LEVEL=info \
    OPENLIST_ENABLED=true \
    OPENLIST_PORT=5244 \
    TZ=Asia/Shanghai

EXPOSE 8080 42069/tcp 42069/udp

VOLUME ["/app/data", "/app/strm", "/app/mounts"]

ENTRYPOINT ["/app/start.sh"]
