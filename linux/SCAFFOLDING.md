# Linux 平台脚手架（未验证）

ClashMiao 在 Linux 上的代理实现走 **FFI + 系统代理（GNOME / Wayland 环境变量）**：
- Flutter 端 `FFIBoxService` 通过 `dart:ffi` 加载 `libcore.so`
- sing-box 内核绑 mixed inbound `127.0.0.1:2080`
- TUN 模式可选（需要 `CAP_NET_ADMIN`，pkexec / setcap，先不默认开）

## 验证前必做（用户在 Linux 机器上）

1. **编译 libcore.so**

   在该 Linux 机器上：
   ```bash
   cd core
   ./build.sh linux
   # 产物: core/output/libcore-linux-amd64.so
   ```

2. **放到 `linux/libs/libcore.so`**
   ```bash
   cp core/output/libcore-linux-amd64.so linux/libs/libcore.so
   ```
   `linux/CMakeLists.txt` 已配 install 到 `${INSTALL_BUNDLE_LIB_DIR}`（即 `lib/`），由
   `CMAKE_INSTALL_RPATH=$ORIGIN/lib` 让 ELF 二进制找到。

3. **`flutter build linux`** 编出 `bundle/clashmiao` + `bundle/lib/`。

## 系统代理（环境变量方式）

sing-box 启动 mixed inbound 后，用户需要：
- 在 GNOME Settings → Network → Network Proxy 设 Manual: HTTP/HTTPS `127.0.0.1:2080`
- 或 export `HTTP_PROXY=http://127.0.0.1:2080 HTTPS_PROXY=...` 给特定终端

我们 **不** 自动改 gsettings —— 不同 DE（GNOME/KDE/XFCE）API 不同，用户手动配更稳。
之后可以做一个小 helper script `bin/clashmiao-setproxy.sh`。

## TUN 模式（可选 milestone）

要做全局 TUN：
- pkexec 拿 root，或 `setcap cap_net_admin+ep`
- sing-box tun inbound auto_route + strict_route
- 跟 NetworkManager / systemd-networkd 协同

## 不验证的部分

- 没在 Linux 桌面跑过 `flutter build linux`
- 没验证 libcore.so 的 cgo 导出符号是否对得上 FFI

拿到 Linux 机器后，预期会有 minor 适配。
