#!/bin/sh
# 进容器执行命令。不带参数就是交互 shell。
W=/var/tmp/android
P=$(cat $W/pid 2>/dev/null)
[ -n "$P" ] && kill -0 $P 2>/dev/null || { echo "Android container is not running"; exit 1; }
NS=$(readlink /proc/$P/ns/pid)
for d in /proc/[0-9]*; do
	[ "$(readlink $d/ns/pid 2>/dev/null)" = "$NS" ] &&
		grep -q BOOTCLASSPATH $d/environ 2>/dev/null && E=$d/environ && break
done
ENV=$(tr '\0' ' ' < ${E:-/proc/$P/environ})
[ -e /proc/$P/ns/pid ] || exec chroot /proc/$P/root /system/bin/env -i $ENV /system/bin/sh ${1:+-c "$*"}
exec nsenter -t $P -m -u -i -n -p -r -w /system/bin/env -i $ENV /system/bin/sh ${1:+-c "$*"}
