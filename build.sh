#!/bin/zsh
# 编译并打包 / Build and bundle
#   ./build.sh             生成 build/NotchPad.app（本机架构）/ build/NotchPad.app for this Mac
#   ./build.sh --release   同时编译 Apple 芯片和 Intel，打包成 dist/NotchPad-<版本>.zip
#                          universal build, zipped to dist/NotchPad-<version>.zip
# 需要 Xcode 或 Command Line Tools（xcode-select --install）。
# Needs Xcode or the Command Line Tools (xcode-select --install).
set -euo pipefail
cd "$(dirname "$0")"

RELEASE=0
[[ ${1:-} == --release ]] && RELEASE=1

APP=build/NotchPad.app
mkdir -p .build build

# 有的机器上编译器和默认 SDK 版本对不上，所以先试默认 SDK，不行再依次试其他已装的 SDK
# On some machines the compiler and the default SDK don't match, so try the default SDK
# first and fall back to the other installed ones.
sdks=("$(xcrun --show-sdk-path 2>/dev/null || true)" /Library/Developer/CommandLineTools/SDKs/MacOSX[0-9]*.sdk(NOn))
SDK=""

compile() {  # $1 = arm64 | x86_64, $2 = 输出 / output
  local sdk log=.build/compile.log
  for sdk in ${SDK:+$SDK} $sdks; do
    [[ -d $sdk ]] || continue
    if swiftc -O -swift-version 5 -target "$1-apple-macosx14.0" -sdk "$sdk" Sources/NotchPad/*.swift -o "$2" 2>"$log"; then
      SDK=$sdk
      echo "  $1 ✓ ($(basename $sdk))"
      return 0
    fi
    # 只有「SDK 和编译器对不上」才换下一个 SDK；代码本身的错误直接报出来
    # Only an SDK/compiler mismatch moves on to the next SDK; real code errors stop here
    grep -q "SDK is not supported by the compiler" "$log" || { cat "$log" >&2; return 1; }
  done
  cat "$log" >&2
  echo "没有找到能用的 SDK。请安装或更新 Xcode / Command Line Tools。" >&2
  echo "No usable SDK found. Install or update Xcode / the Command Line Tools." >&2
  return 1
}

echo "编译中 / Compiling…"
if (( RELEASE )); then
  compile arm64 .build/NotchPad-arm64
  compile x86_64 .build/NotchPad-x86_64
  lipo -create .build/NotchPad-arm64 .build/NotchPad-x86_64 -output .build/NotchPad
else
  compile "$(uname -m)" .build/NotchPad
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/NotchPad "$APP/Contents/MacOS/NotchPad"
cp Info.plist "$APP/Contents/Info.plist"
cp -R Resources/. "$APP/Contents/Resources/"
# 本机自签（没有苹果开发者证书）/ ad-hoc signature (no Apple Developer ID)
codesign --force --sign - "$APP"
echo "✓ $APP"

if (( RELEASE )); then
  VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
  mkdir -p dist
  ZIP="dist/NotchPad-$VERSION.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "✓ $ZIP"
fi
