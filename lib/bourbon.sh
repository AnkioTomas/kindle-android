# KT2 / Bourbon。系统分区和开机内核不动。
# 根文件系统是用户分区上的镜像，卸载就是删掉安装目录。

bourbon_screen() {
	eips -c
	eips 2 1 "$1"
	eips 5 1 "$2"
	eips 8 1 "$3"
	eips 11 1 "$4"
	eips 14 1 "stop.sh returns"
	eips 17 1 "system partition kept"
}

bourbon_thaw() {
	[ -f $W/bourbon.frozen ] || return 0
	while read -r p; do
		kill -CONT $p 2>/dev/null
	done < $W/bourbon.frozen
	rm -f $W/bourbon.frozen
}

bourbon_freeze() {
	rm -f $W/bourbon.frozen
	for d in /proc/[0-9]*; do
		c=$(tr -d '\0' < $d/comm 2>/dev/null) || continue
		case $c in
		cvm|reader.lua|Xorg|awesome|pillowd|blanket)
			kill -STOP ${d#/proc/} 2>/dev/null && echo ${d#/proc/} >> $W/bourbon.frozen
			;;
		esac
	done
}

bourbon_loop_free() {
	i=1
	while [ $i -le 15 ]; do
		for n in /dev/loop/$i /dev/loop$i; do
			[ -b "$n" ] || continue
			if ! losetup "$n" >/dev/null 2>&1; then
				echo "$n"
				return 0
			fi
		done
		i=$((i + 1))
	done
	return 1
}

bourbon_attach() {
	dev=$(bourbon_loop_free) || return 1
	losetup "$dev" "$1" >/dev/null || return 1
	echo "$dev" >> $W/bourbon.loops
	echo "$dev"
}

bourbon_release() {
	if [ -f $W/bourbon.loops ]; then
		while read -r n; do
			losetup -d "$n" 2>/dev/null
		done < $W/bourbon.loops
		rm -f $W/bourbon.loops
	fi
	rmmod binder 2>/dev/null
	rmmod ashmem 2>/dev/null
}

bourbon_hold() {
	lj=
	for c in /mnt/base-us/koreader/luajit /mnt/us/koreader/luajit; do
		[ -f "$c" ] && lj=$c && break
	done
	[ -n "$lj" ] || return 1
	cp "$lj" $W/luajit && chmod 755 $W/luajit || return 1
	rm -f $W/bourbon.stop $W/bourbon.ready
	if command -v setsid >/dev/null 2>&1; then
		setsid $W/luajit $D/src/bourbon.lua </dev/null >/dev/null 2>&1 &
	else
		nohup $W/luajit $D/src/bourbon.lua </dev/null >/dev/null 2>&1 &
	fi
	echo $! > $W/bourbon.hold
	i=0
	while [ ! -f $W/bourbon.ready ] && kill -0 $(cat $W/bourbon.hold) 2>/dev/null && [ $i -lt 50 ]; do
		usleep 100000
		i=$((i + 1))
	done
	[ -f $W/bourbon.ready ]
}

bourbon_root_sh() {
	cat > $W/bourbon-root.sh << EOF
#!/bin/sh
exec >>$W/bourbon.log 2>&1
R=$W/root
mkdir -p \$R/proc \$R/sys \$R/dev/graphics \$R/dev/input \$R/dev/pts \$R/dev/socket \$R/mnt
mount -t proc proc \$R/proc
mount -t sysfs sys \$R/sys
mount -t tmpfs -o mode=755 tmp \$R/dev
mount -t tmpfs tmp \$R/mnt
mkdir -p \$R/dev/graphics \$R/dev/input \$R/dev/pts \$R/dev/socket
touch \$R/dev/fb0 \$R/dev/graphics/fb0
mknod \$R/dev/null c 1 3
mknod \$R/dev/zero c 1 5
mknod \$R/dev/full c 1 7
mknod \$R/dev/random c 1 8
mknod \$R/dev/urandom c 1 9
mknod \$R/dev/tty c 5 0
mknod \$R/dev/ptmx c 5 2
mknod \$R/dev/binder c 10 $1
mknod \$R/dev/ashmem c 10 $2
chmod 666 \$R/dev/null \$R/dev/zero \$R/dev/full \$R/dev/random \$R/dev/urandom \$R/dev/tty \$R/dev/ptmx \$R/dev/binder \$R/dev/ashmem
# 空 trie 能让 sh 活下来，但 ro.kernel.qemu 读成 0，软件 GLES 不会加载。
if [ -x $W/propseed ]; then
	$W/propseed \$R/system/build.prop \$R/dev/__properties__ || \
		dd if=/dev/zero of=\$R/dev/__properties__ bs=1024 count=128 2>/dev/null
else
	dd if=/dev/zero of=\$R/dev/__properties__ bs=1024 count=128 2>/dev/null
	printf '\024\0\0\0\0\0\0\0PROP\253\320\156\374' > $W/prophdr
	dd if=$W/prophdr of=\$R/dev/__properties__ conv=notrunc 2>/dev/null
fi
chmod 444 \$R/dev/__properties__
mount -t devpts devpts \$R/dev/pts
mount --bind /dev/fb0 \$R/dev/graphics/fb0
mount --bind /dev/fb0 \$R/dev/fb0
mount --bind /dev/input \$R/dev/input
chmod 666 \$R/dev/input/event0 \$R/dev/input/event1 2>/dev/null
	cp $W/bourbon-init.sh \$R/mnt/init.sh
	chmod 755 \$R/mnt/init.sh
	if [ -x $W/andsocks ]; then
		cp $W/andsocks \$R/mnt/andsocks
		chmod 755 \$R/mnt/andsocks
	fi
	if [ -x $W/batsvc ]; then
		cp $W/batsvc \$R/mnt/batsvc
		chmod 755 \$R/mnt/batsvc
	fi
exec chroot \$R /system/bin/sh /mnt/init.sh
EOF
	cat > $W/bourbon-init.sh << 'EOF'
#!/system/bin/sh
# 不跑官方 init。它会写 panic_on_oops，也会碰 mmc。
export ANDROID_ROOT=/system
export ANDROID_DATA=/data
mkdir -p /data/local/tmp /dev/socket
/system/bin/servicemanager >/data/sm.log 2>&1 &
echo $! >/data/sm.pid
/system/bin/sleep 1
/system/bin/surfaceflinger >/data/sf.log 2>&1 &
echo $! >/data/sf.pid
/system/bin/sleep 2
if [ -x /mnt/batsvc ]; then
	/mnt/batsvc &
fi
chmod 666 /dev/input/event0 /dev/input/event1
# 堆放大以后 zygote 的虚拟地址超过 200MB，默认 overcommit 会拒绝 fork
echo 1 > /proc/sys/vm/overcommit_memory
if [ -x /system/bin/dnsd ]; then
	/system/bin/dnsd /dev/socket/dnsproxyd >/data/dnsd.log 2>&1 &
fi
/mnt/andsocks
while true; do
	/system/bin/sleep 3600
done
EOF
	chmod 755 $W/bourbon-root.sh
}

bourbon_shot() {
	cat > $W/bourbon-shot.sh << EOF
#!/bin/sh
i=0
while [ \$i -lt 30 ]; do
	[ -s $W/root/data/sf.pid ] && break
	sleep 1
	i=\$((i + 1))
done
sleep 8
line=\$(cat /sys/class/graphics/fb0/stride 2>/dev/null)
y=\$(cat /sys/class/graphics/fb0/yres 2>/dev/null)
off=\$(cat /sys/class/graphics/fb0/yoffset 2>/dev/null)
[ -n "\$line" ] || line=608
[ -n "\$y" ] || y=800
[ -n "\$off" ] || off=0
dd if=/dev/fb0 of=$S/screen.raw bs="\$line" skip="\$off" count="\$y" 2>/dev/null
echo "\$line \$y \$off" > $S/screen.geom
ns=\$(cat $W/bourbon.ns 2>/dev/null)
ssid=\$(wpa_cli -i wlan0 status 2>/dev/null | sed -n 's/^ssid=//p')
if [ -n "\$ns" ] && [ -n "\$ssid" ]; then
	echo "\$ssid" > /proc/\$ns/root/dev/kfb/ssid
	chmod 644 /proc/\$ns/root/dev/kfb/ssid
fi
touch $W/bourbon.refresh
EOF
	chmod 755 $W/bourbon-shot.sh
	if command -v setsid >/dev/null 2>&1; then
		setsid $W/bourbon-shot.sh </dev/null >/dev/null 2>&1 &
	else
		nohup $W/bourbon-shot.sh </dev/null >/dev/null 2>&1 &
	fi
}

bourbon_android() {
	lipc-set-prop -i com.lab126.powerd preventScreenSaver 1
	mkdir -p $W $S
	if [ -f $W/bourbon.pid ] && kill -0 $(cat $W/bourbon.pid 2>/dev/null) 2>/dev/null; then
		t "bourbon already up"
		return 0
	fi
	img=
	for c in $D/images/system.img $D/images/esystem.bin /mnt/base-us/esystem.bin; do
		[ -f "$c" ] && img=$c && break
	done
	if [ -z "$img" ]; then
		bourbon_screen "kindle-android" "image missing" "user store only" "partition not written"
		return 1
	fi
	ko=
	for c in $D/bin/binder.ko $D/binder.ko; do
		[ -f "$c" ] && ko=$c && break
	done
	ako=
	for c in $D/bin/ashmem.ko $D/ashmem.ko; do
		[ -f "$c" ] && ako=$c && break
	done
	bourbon_hold || t "bourbon: fb hold failed"
	bourbon_freeze
	rm -f $W/bourbon.loops
	if [ ! -f $S/data.img ]; then
		dd if=/dev/zero of=$S/data.img bs=1048576 count=64 2>/dev/null || {
			bourbon_screen "kindle-android" "data image failed" "user store only" "partition not written"
			bourbon_thaw
			return 1
		}
		mke2fs -F -L data $S/data.img >/dev/null 2>&1 || {
			rm -f $S/data.img
			bourbon_screen "kindle-android" "mke2fs data failed" "user store only" "partition not written"
			bourbon_thaw
			return 1
		}
	fi
	sys=$(bourbon_attach "$img") || {
		bourbon_screen "kindle-android" "no free loop" "user store only" "partition not written"
		bourbon_thaw
		bourbon_release
		return 1
	}
	dat=$(bourbon_attach $S/data.img) || {
		bourbon_screen "kindle-android" "data loop failed" "user store only" "partition not written"
		bourbon_thaw
		bourbon_release
		return 1
	}
	mkdir -p $W/root/system $W/root/data
	mount -o ro "$sys" $W/root/system || {
		bourbon_screen "kindle-android" "system mount failed" "user store only" "partition not written"
		bourbon_thaw
		bourbon_release
		return 1
	}
	mount -o rw "$dat" $W/root/data || {
		umount $W/root/system
		bourbon_screen "kindle-android" "data mount failed" "user store only" "partition not written"
		bourbon_thaw
		bourbon_release
		return 1
	}
	if [ -z "$ko" ] || [ -z "$ako" ]; then
		bourbon_screen "Android 4.4" "root is on user store" "binder.ko missing" "partition not written"
		[ -f $W/bourbon.hold ] && cp $W/bourbon.hold $W/bourbon.pid
		return 0
	fi
	cp "$ko" $W/binder.ko
	cp "$ako" $W/ashmem.ko
	seed=
	for c in $D/bin/propseed $D/propseed; do
		[ -f "$c" ] && seed=$c && break
	done
	if [ -n "$seed" ]; then
		cp "$seed" $W/propseed && chmod 755 $W/propseed
	fi
	for c in $D/bin/andsocks $D/andsocks; do
		[ -f "$c" ] && cp "$c" $W/andsocks && chmod 755 $W/andsocks && break
	done
	for c in $D/bin/batsvc $D/batsvc; do
		[ -f "$c" ] && cp "$c" $W/batsvc && chmod 755 $W/batsvc && break
	done
	insmod $W/binder.ko 2>/dev/null || grep -q ' binder$' /proc/misc || {
		bourbon_screen "Android 4.4" "insmod binder failed" "module left unloaded" "partition not written"
		[ -f $W/bourbon.hold ] && cp $W/bourbon.hold $W/bourbon.pid
		return 0
	}
	insmod $W/ashmem.ko 2>/dev/null || grep -q ' ashmem$' /proc/misc || {
		bourbon_screen "Android 4.4" "insmod ashmem failed" "binder left loaded" "partition not written"
		[ -f $W/bourbon.hold ] && cp $W/bourbon.hold $W/bourbon.pid
		return 0
	}
	bminor=$(awk '$2=="binder"{print $1}' /proc/misc)
	aminor=$(awk '$2=="ashmem"{print $1}' /proc/misc)
	bourbon_root_sh "$bminor" "$aminor"
	if command -v setsid >/dev/null 2>&1; then
		setsid unshare -m sh $W/bourbon-root.sh </dev/null >/dev/null 2>&1 &
	else
		nohup unshare -m sh $W/bourbon-root.sh </dev/null >/dev/null 2>&1 &
	fi
	echo $! > $W/bourbon.ns
	if [ -f $W/bourbon.hold ]; then
		cp $W/bourbon.hold $W/bourbon.pid
	else
		cp $W/bourbon.ns $W/bourbon.pid
	fi
	bourbon_shot
	t "bourbon android pid=$(cat $W/bourbon.pid)"
}
