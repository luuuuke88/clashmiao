# libcore.dll 二进制位置（构建时由 CMake 拷贝到运行时目录）

把 `core/build.sh windows` 编出的 `core/output/libcore-windows-amd64.dll` 拷贝到这里改名 `libcore.dll`：

```
cp core/output/libcore-windows-amd64.dll windows/libs/libcore.dll
```

`windows/runner/CMakeLists.txt` 会在 install 阶段把这个文件拷到 `${INSTALL_BUNDLE_LIB_DIR}/libcore.dll`（即 .exe 同目录），FFI `DynamicLibrary.open('libcore.dll')` 即可加载。
