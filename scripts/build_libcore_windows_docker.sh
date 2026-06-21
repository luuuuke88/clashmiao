#!/usr/bin/env bash
set -euo pipefail

apt-get update -q
apt-get install -y -q gcc-mingw-w64-x86-64

CGO_ENABLED=1 \
GOOS=windows \
GOARCH=amd64 \
CC=x86_64-w64-mingw32-gcc \
go build \
  -trimpath \
  -buildmode=c-shared \
  -ldflags="-w -s" \
  -tags with_gvisor,with_quic,with_wireguard,with_ech,with_utls,with_clash_api,with_grpc \
  -o /out/libcore.dll \
  ./custom

ls -lh /out/libcore.dll
