#!/bin/sh
# 在有 armhf 交叉编译器的机器上编宿主程序。
#   CROSS=arm-linux-gnueabihf- sh src/build.sh
# 产物进 bin/。fbink 和 slirp4netns 不在这里编，见 README。
set -e
cd "$(dirname "$0")/.."
: "${CROSS:?set CROSS to the armhf toolchain prefix, e.g. arm-linux-gnueabihf-}"
mkdir -p bin
"$CROSS"gcc -Os -s -o bin/kafstub src/kafstub.c -ldl
"$CROSS"gcc -Os -s -o bin/loopdio src/loopdio.c
"$CROSS"gcc -Os -static -s -o bin/slirpfwd src/slirpfwd.c
"$CROSS"gcc -Os -static -s -o bin/pivot_init src/pivot_init.c
"$CROSS"gcc -Os -s -o bin/keyinject src/keyinject.c
