# libcore.so 二进制位置（构建时由 CMake 拷贝到运行时目录）

把 `core/build.sh linux` 编出的 `core/output/libcore-linux-amd64.so` 拷贝到这里改名 `libcore.so`：

```
cp core/output/libcore-linux-amd64.so linux/libs/libcore.so
```

`linux/CMakeLists.txt` 会在 install 阶段把这个文件拷到 `${INSTALL_BUNDLE_LIB_DIR}/libcore.so`（与 ELF 二进制同目录，由 rpath `$ORIGIN/lib/` 找到），FFI `DynamicLibrary.open('libcore.so')` 即可加载。
