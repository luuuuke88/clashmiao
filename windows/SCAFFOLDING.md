# Windows 平台脚手架（未验证）

ClashMiao 在 Windows 上的代理实现走 **FFI + 系统代理**：
- Flutter 端 `FFIBoxService` (`lib/core/box_service/ffi_box_service.dart`) 通过 `dart:ffi` 加载 `libcore.dll`
- sing-box 内核以 mixed inbound 绑 `127.0.0.1:2080`，sing-box 自己设置 Windows 系统代理（Wininet）
- 暂不接 WinTun（需要 admin + 驱动签名，复杂度高，先用系统代理覆盖 80% 场景）

## 验证前必做（用户在 Windows 机器上）

1. **编译 libcore.dll**

   在 macOS / Linux 上（带 MinGW 交叉编译器）：
   ```bash
   cd core
   ./build.sh windows
   # 产物: core/output/libcore-windows-amd64.dll
   ```

   或者直接在 Windows 机器上（需 Go 1.21+ + MinGW-w64）：
   ```powershell
   cd core
   bash build.sh windows  # 用 git-bash
   ```

2. **把 dll 放到 `windows/libs/libcore.dll`**
   ```bash
   cp core/output/libcore-windows-amd64.dll windows/libs/libcore.dll
   ```
   `windows/runner/CMakeLists.txt` 已配 `install(FILES libs/libcore.dll DESTINATION ${CMAKE_INSTALL_PREFIX})` —— 它会被拷到 `build/windows/runner/Release/libcore.dll` 与 `clashmiao.exe` 同级。

3. **`flutter build windows`** 编出 `.exe` + 依赖。

## 已知 TODO

- `default_config_options.dart` 的 `set-system-proxy: true`（桌面默认 true）在 Windows 需要管理员才能写 IE 注册表。如果失败，sing-box 会 fallback 到不设系统代理，用户需手动配 mixed proxy 127.0.0.1:2080。
- Windows MSIX 打包：参考 baseproxy `windows/packaging/msix/` 的思路自己写，注意签名证书。
- WinTun 全局 TUN 模式：以后单独 milestone，需要 WinTun driver + admin。

## 不验证的部分

代码上 FFI 是跨平台同一份，理论上跑得通。但**作者没有 Windows 物理机**，所以：
- 没在 Windows 上跑过 `flutter build windows`
- 没在 Windows 上验证 system proxy 是否真被改
- 没在 Windows 上验证 sing-box dll 的导出符号跟 FFI binding 完全对得上

拿到 Windows 机器后，按上面流程跑一遍，预期会有少量适配（CGo 编译参数、dll 导出名等）。
