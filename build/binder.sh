#!/bin/sh
# 给 KT2 的 3.0.35-lab126 编 binder 和 ashmem。不替换开机内核。
#   KDIR=/path/to/configured/linux-3.0.35-lab126 sh build/binder.sh
# 这棵树需要先 make ARCH=arm <wario_defconfig> && make ARCH=arm modules_prepare。
set -e
cd "$(dirname "$0")/.."
: "${KDIR:?set KDIR to a prepared 3.0.35-lab126 tree}"
[ -f "$KDIR/Module.symvers" ] || [ -f "$KDIR/.config" ] || {
	echo "KDIR is not configured"
	exit 1
}
if [ ! -f "$KDIR/include/linux/compiler-gcc12.h" ]; then
	printf '%s\n' '#include <linux/compiler-gccN.h>' \
		> "$KDIR/include/linux/compiler-gcc12.h"
fi
mkdir -p bin
make -C "$KDIR" ARCH=arm KCFLAGS="-march=armv7-a" M="$PWD/system/kernel/android" modules
cp system/kernel/android/binder.ko system/kernel/android/ashmem.ko bin/
