# libcore.so

预编译的 sing-box 核心动态库（linux/amd64，CGo `-buildmode=c-shared`），通过 Git LFS 入库。

`linux/CMakeLists.txt` 的 install 阶段会把它拷到 `bundle/lib/` 下，CMAKE_INSTALL_RPATH=`$ORIGIN/lib` 让 ELF 二进制找到，Dart FFI `DynamicLibrary.open('libcore.so')` 直接加载。

导出符号：`setup` / `setupOnce` / `start` / `stop` / `parse` / `generateConfig` / `selectOutbound` / `urlTest` / `changeConfigOptions` / `startCommandClient` / `stopCommandClient`。

替换步骤（更新 sing-box 版本时）：

```bash
docker run --rm --platform linux/amd64 \
  -v <go-source-dir>:/src:ro -v $(pwd):/out \
  -w /work golang:1.22-bookworm bash -c '
    cp -r /src/. /work/
    CGO_ENABLED=1 GOOS=linux GOARCH=amd64 \
      go build -trimpath -buildmode=c-shared -ldflags="-w -s" \
      -tags with_gvisor,with_quic,with_wireguard,with_ech,with_utls,with_clash_api,with_grpc \
      -o /out/libcore.so ./custom
  '
git lfs track linux/libs/libcore.so
git add linux/libs/libcore.so && git commit -m "build(linux): refresh libcore.so"
```
