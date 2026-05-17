# libcore.dll

预编译的 sing-box 核心动态库（amd64，CGo `-buildmode=c-shared`），通过 Git LFS 入库。

`windows/runner/CMakeLists.txt` 的 install 阶段会把它拷到 `.exe` 同目录，Dart FFI `DynamicLibrary.open('libcore.dll')` 直接加载。

导出符号：`setup` / `setupOnce` / `start` / `stop` / `parse` / `generateConfig` / `selectOutbound` / `urlTest` / `changeConfigOptions` / `startCommandClient` / `stopCommandClient`。

替换步骤（更新 sing-box 版本时）：

```bash
# 在 macOS / Linux 主机上交叉编译（依赖 Docker）
docker run --rm --platform linux/amd64 \
  -v <go-source-dir>:/src:ro -v $(pwd):/out \
  -w /work golang:1.22-bookworm bash -c '
    cp -r /src/. /work/
    apt-get update -q && apt-get install -y -q gcc-mingw-w64-x86-64
    CGO_ENABLED=1 GOOS=windows GOARCH=amd64 CC=x86_64-w64-mingw32-gcc \
      go build -trimpath -buildmode=c-shared -ldflags="-w -s" \
      -tags with_gvisor,with_quic,with_wireguard,with_ech,with_utls,with_clash_api,with_grpc \
      -o /out/libcore.dll ./custom
  '
git lfs track windows/libs/libcore.dll
git add windows/libs/libcore.dll && git commit -m "build(windows): refresh libcore.dll"
```
