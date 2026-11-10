#!/bin/sh
W=/var/tmp/android
PLATFORM=kindle
U=/mnt/base-us
[ -d /mnt/onboard/.kobo ] && PLATFORM=kobo && U=/mnt/onboard
here=$(cd "$(dirname "$0")" && pwd)
S=$U/system/$(basename "$here")
BIN=$here/bin
[ -x $W/bin/fbink ] && BIN=$W/bin
RS=
[ -f $W/restarting ] && RS=1
if [ -f $W/bourbon.pid ] || [ -f $W/bourbon.ns ] || [ -f $W/bourbon.frozen ] || [ -f $W/bourbon.loops ]; then
	touch $W/bourbon.stop
	for f in bourbon.ns bourbon.pid bourbon.hold; do
		p=$(cat $W/$f 2>/dev/null)
		[ -n "$p" ] && kill $p 2>/dev/null
	done
	i=0
	while [ $i -lt 50 ]; do
		alive=
		for f in bourbon.ns bourbon.hold; do
			p=$(cat $W/$f 2>/dev/null)
			[ -n "$p" ] && kill -0 $p 2>/dev/null && alive=1
		done
		[ -n "$alive" ] || break
		usleep 100000
		i=$((i + 1))
	done
	umount $W/root/data 2>/dev/null
	umount $W/root/system 2>/dev/null
	umount $W/root 2>/dev/null
	if [ -f $W/bourbon.loops ]; then
		while read -r n; do
			losetup -d "$n" 2>/dev/null
		done < $W/bourbon.loops
	fi
	rmmod binder 2>/dev/null
	rmmod ashmem 2>/dev/null
	while read -r p; do kill -CONT $p 2>/dev/null; done < $W/bourbon.frozen
	rm -f $W/bourbon.pid $W/bourbon.ns $W/bourbon.hold $W/bourbon.stop $W/bourbon.ready $W/bourbon.frozen $W/bourbon.loops
fi
ps=
for f in watchdog sleep lipc slirp kfb kfbhold filebrowser kafstub keyinject; do
	p=$(cat $W/$f.pid 2>/dev/null)
	[ "$p" = "$PPID" ] && continue
	[ -n "$p" ] && kill $p 2>/dev/null && ps="$ps $p"
done
for u in $(pgrep -f "^unshare -m -u -i -n -p -f -- sh .*--in-ns"); do
	for p in $(cat /proc/$u/task/$u/children 2>/dev/null) $u; do
		kill -9 $p 2>/dev/null && ps="$ps $p"
	done
done
mn=$(cat $W/mntns 2>/dev/null)
[ -e /proc/self/ns/pid ] || [ -z "$mn" ] || for p in /proc/[0-9]*; do
	[ "$(readlink $p/ns/mnt 2>/dev/null)" = "$mn" ] && kill -9 ${p#/proc/} 2>/dev/null && ps="$ps ${p#/proc/}"
done
for p in $(pgrep -f "^[^ ]*/slirp4netns .*--api-socket $W/slirp.sock"); do
	kill $p 2>/dev/null && ps="$ps $p"
done
i=0
while [ -n "$ps" ] && [ $i -lt 10 ]; do
	a=
	for p in $ps; do kill -0 $p 2>/dev/null && a=1; done
	[ -n "$a" ] || break
	usleep 100000
	i=$((i + 1))
done
for p in $ps; do kill -9 $p 2>/dev/null; done
for f in watchdog sleep lipc slirp kfb kfbhold filebrowser kafstub keyinject; do rm -f $W/$f.pid; done
rm -f $W/pid $W/mntns
[ -d $W/kfb/ctl ] && { [ -f $W/kfb/ctl/invert ] && touch $S/invert || rm -f $S/invert; }
for m in $(cat $W/fb.mounts 2>/dev/null); do umount -l $m; done
rm -f $W/fb.mounts
if [ -f $W/zram.state ]; then
	read sw pc < $W/zram.state
	echo $sw > /proc/sys/vm/swappiness
	[ -n "$pc" ] && echo $pc > /proc/sys/vm/page-cluster
	rm -f $W/zram.state
fi
[ -f $W/wifi.ps ] && rm -f $W/wifi.ps && iwconfig wlan0 power on 2>/dev/null
unmount_rootfs() {
	for m in $U/system/*/rootfs $W/kfb; do
		while grep -q " $m " /proc/mounts; do umount -l $m || break; done
	done
}
FAT=
grep -q " $U vfat " /proc/mounts && FAT=1
if [ -z "$RS" ] && [ "$1" != --stale ] && [ -n "$FAT" ]; then
	. "$here/lib/userstore.sh"
	while grep -q " $W/kfb " /proc/mounts; do umount -l $W/kfb || break; done
	us_umount $S/rootfs
	us_umount $S/data
	fatloop_restore
fi
. "$here/platform/$PLATFORM.sh"
net_cleanup
[ -n "$RS" ] || framework_start
if [ -n "$FAT" ]; then
	while grep -q " $W/kfb " /proc/mounts; do umount -l $W/kfb || break; done
else
	unmount_rootfs
fi
echo stopped
