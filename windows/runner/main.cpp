#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

// 单实例检测用的具名 Mutex。名字带上应用标识，避免和其它程序的同名 Mutex 撞车。
const wchar_t kSingleInstanceMutexName[] = L"ClashMiao_SingleInstance_Mutex";

// 如果已经有一份实例在跑，把它的主窗口拉到前台——按窗口标题查找（下面
// window.Create(L"clashmiao", ...) 设置的就是这个标题，win32_window.cpp
// 里直接把 title 传给 CreateWindowExW 作为窗口文本，没有被后续代码改过）。
// 找不到窗口不算错误，就单纯放弃激活，直接退出当前（重复启动的）进程。
void ActivateExistingInstance() {
  HWND existing = ::FindWindowW(nullptr, L"clashmiao");
  if (existing == nullptr) {
    return;
  }
  if (::IsIconic(existing)) {
    ::ShowWindow(existing, SW_RESTORE);
  }
  ::SetForegroundWindow(existing);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // 单实例检测：具名 Mutex 是 Windows 标准做法。CreateMutexW 在第二次启动时
  // 依然会成功返回一个句柄，但紧跟着的 GetLastError() 会带上
  // ERROR_ALREADY_EXISTS——用这个信号判断"已经有一份在跑"，激活老窗口后
  // 直接退出，不再往下走 Flutter engine / 窗口创建流程，避免重复启动多进程
  // （多个 sing-box 核心实例抢同一个 TUN / 系统代理设置）。
  HANDLE single_instance_mutex =
      ::CreateMutexW(nullptr, FALSE, kSingleInstanceMutexName);
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    ActivateExistingInstance();
    if (single_instance_mutex != nullptr) {
      ::CloseHandle(single_instance_mutex);
    }
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"clashmiao", origin, size)) {
    ::CloseHandle(single_instance_mutex);
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  ::CloseHandle(single_instance_mutex);
  return EXIT_SUCCESS;
}
