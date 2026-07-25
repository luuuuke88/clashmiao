#!/usr/bin/env bash
# package-linux.sh — 把 `flutter build linux --release` 的产物打成两种
# Linux 用户真的会下载的格式：
#
#   1. tar.gz  —— 解开就能跑，任何发行版通用，不需要 root
#   2. .deb    —— Debian/Ubuntu（绝大多数 Linux 桌面用户）双击安装
#
# 用法：bin/package-linux.sh <version>      例如 bin/package-linux.sh 1.2.3
#
# 没做 AppImage：它需要 appimagetool + FUSE，在 CI 里要 `--appimage-extract-and-run`
# 绕 FUSE，多一层容易坏的依赖。tar.gz 已经覆盖了"便携、免安装"这个诉求，
# 等有人真的要 AppImage 再加。
set -euo pipefail

VERSION="${1:?用法: bin/package-linux.sh <version>}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

BUNDLE="build/linux/x64/release/bundle"
OUT="build/release"
APP_ID="clashmiao"

log() { printf '\033[0;32m[package-linux]\033[0m %s\n' "$*"; }
die() { printf '\033[0;31m[package-linux]\033[0m %s\n' "$*" >&2; exit 1; }

[ -d "$BUNDLE" ] || die "找不到 $BUNDLE，先跑 flutter build linux --release"
[ -x "$BUNDLE/clashmiao" ] || die "$BUNDLE/clashmiao 不存在或不可执行"

mkdir -p "$OUT"

# ---------------------------------------------------------------- tar.gz
TARBALL="$OUT/ClashMiao-Linux-x86_64-$VERSION.tar.gz"
rm -f "$TARBALL"
# 用 --transform 把顶层目录换成带版本号的名字，解开后不是一个叫 "bundle"
# 的目录（那样用户同时解两个版本会互相覆盖）。
tar -czf "$TARBALL" \
  --transform "s,^\\.,ClashMiao-$VERSION," \
  -C "$BUNDLE" .
log "tar.gz: $TARBALL ($(du -h "$TARBALL" | cut -f1))"

# ------------------------------------------------------------------- deb
DEB_ROOT="build/deb/$APP_ID"
rm -rf "$DEB_ROOT"
mkdir -p "$DEB_ROOT/DEBIAN" \
         "$DEB_ROOT/usr/lib/$APP_ID" \
         "$DEB_ROOT/usr/bin" \
         "$DEB_ROOT/usr/share/applications" \
         "$DEB_ROOT/usr/share/icons/hicolor"

cp -r "$BUNDLE"/. "$DEB_ROOT/usr/lib/$APP_ID/"

# /usr/bin 里放一个软链接而不是复制二进制：Flutter 产物依赖同目录下的
# lib/ 和 data/，直接把可执行文件复制到 /usr/bin 会找不到它们。
ln -sf "/usr/lib/$APP_ID/clashmiao" "$DEB_ROOT/usr/bin/$APP_ID"

# 图标：复用 macOS 的 AppIcon 资源（那是唯一一套完整多尺寸图标）。
ICON_SRC="macos/Runner/Assets.xcassets/AppIcon.appiconset"
for size in 32 64 128 256 512; do
  src="$ICON_SRC/app_icon_$size.png"
  [ -f "$src" ] || continue
  dest_dir="$DEB_ROOT/usr/share/icons/hicolor/${size}x${size}/apps"
  mkdir -p "$dest_dir"
  cp "$src" "$dest_dir/$APP_ID.png"
done

cat > "$DEB_ROOT/usr/share/applications/$APP_ID.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=ClashMiao
GenericName=Proxy Client
Comment=Cross-platform proxy client
Exec=$APP_ID
Icon=$APP_ID
Terminal=false
Categories=Network;
StartupWMClass=clashmiao
DESKTOP

INSTALLED_KB="$(du -sk "$DEB_ROOT" | cut -f1)"
cat > "$DEB_ROOT/DEBIAN/control" <<CONTROL
Package: $APP_ID
Version: $VERSION
Section: net
Priority: optional
Architecture: amd64
Depends: libgtk-3-0, libayatana-appindicator3-1, libcurl4
Installed-Size: $INSTALLED_KB
Maintainer: ClashMiao <noreply@clashmiao.invalid>
Description: Cross-platform proxy client
 A proxy client with subscription management, latency testing and
 smart/global routing modes.
CONTROL

DEB="$OUT/${APP_ID}_${VERSION}_amd64.deb"
rm -f "$DEB"
# --root-owner-group：产出的 deb 里文件属主是 root:root。不加的话会带上
# 构建机器当前用户的 uid/gid，装到别人机器上属主就是错的。
dpkg-deb --build --root-owner-group "$DEB_ROOT" "$DEB" >/dev/null
log "deb: $DEB ($(du -h "$DEB" | cut -f1))"

# 校验而不是假设：deb 结构错了（比如少了 desktop 文件）也能"打包成功"。
dpkg-deb --contents "$DEB" | grep -q "usr/share/applications/$APP_ID.desktop" ||
  die "deb 里没有 .desktop 文件，装完不会出现在应用菜单里"
dpkg-deb --contents "$DEB" | grep -q "usr/lib/$APP_ID/clashmiao" ||
  die "deb 里没有主程序"
dpkg-deb --contents "$DEB" | grep -q "usr/lib/$APP_ID/lib/libcore.so" ||
  die "deb 里没有 libcore.so，装完连不上"

log "完成，产物："
find "$OUT" -maxdepth 1 -type f -printf '  %f (%s bytes)\n' | sort
