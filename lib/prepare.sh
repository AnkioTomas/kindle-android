# 解压系统镜像、挂成只读根。Kindle 的 squashfs 是单线程解压，运行时再读会卡，所以第一次解开后删掉 sqfs。

loop_free() {
	for d in /sys/block/loop[0-9]*; do
		n=${d#/sys/block/loop}
		case "$(cat $d/loop/backing_file 2>/dev/null)" in
			"$1" | "$1 (deleted)")
				grep -q " 7:$n " /proc/self/mountinfo || losetup -d /dev/loop/$n 2>/dev/null ;;
		esac
	done
}

loop_mount() {
	if [ -z "$USERSTORE" ]; then
		for l in /dev/loop/[0-9]*; do
			[ -e /dev/loop${l##*/} ] || mknod /dev/loop${l##*/} b 7 ${l##*/}
		done 2>/dev/null
		mount -t ${3:-squashfs} -o loop,${4:-ro} "$1" "$2" 2>/dev/null && return 0
		t "loop: mount -o loop failed"
	fi
	loop_free "$1"
	n=
	dev=$W/loop.${2##*/}
	for d in /sys/block/loop[0-9]*; do
		[ -d $d/loop ] || { n=${d#/sys/block/loop}; break; }
	done
	[ -n "$n" ] || n=$(losetup -f 2>/dev/null | tr -cd 0-9)
	[ -n "$n" ] && [ -f /sys/block/loop$n/dev ] || return 1
	rm -f $dev
	mknod $dev b $(tr : ' ' < /sys/block/loop$n/dev) || return 1
	losetup $dev "$1" && mount -t ${3:-squashfs} -o ${4:-ro} $dev "$2" && return 0
	losetup -d $dev 2>/dev/null
	rm -f $dev
	return 1
}

cleanup_stale() {
	sh $D/stop.sh --stale >/dev/null 2>&1
}

unpack_images() {
	loop_free $B/images/system.sqfs
	I=$B/images/system.sqfs
	[ -f $I ] || I=$B/images/system.tar.gz
	[ -f $I ] || return 0
	t "unpacking system image"
	N=$S/rootfs.new
	[ -n "$USERSTORE" ] && N=$W/sys.new
	rm -rf $S/rootfs.new
	$BIN/fbink -q -c -f " "
	splash_text "" "正在安装…"
	INSTALLED=1
	M=
	if [ "${I##*.}" = sqfs ]; then
		M=$W/sqfs
		mkdir -p $M && loop_mount $I $M || return 1
		total=$(du -sm $M | cut -f1)
	else
		total=$(cat $B/images/system.mb 2>/dev/null)
	fi
	if [ -n "$USERSTORE" ]; then
		sz=$(us_sys_size ${total:-400})
		us_sys_new $sz || { [ -n "$M" ] && umount $M; return 1; }
	fi
	if [ -n "$M" ]; then cp -a $M/. $N &
	else mkdir -p $N && gzip -dc $I | tar -x -C $N &
	fi
	cp=$!
	i=0
	while kill -0 $cp 2>/dev/null; do
		[ $i -lt 4 ] && splash_text "" "正在安装…"
		i=$((i + 1))
		pct=$(( $(du -sm $N 2>/dev/null | cut -f1) * 100 / ${total:-300} ))
		$BIN/fbink -q -y -10 -P $((pct > 100 ? 100 : pct))
		sleep 1
	done
	wait $cp
	ok=$?
	[ -n "$M" ] && umount $M
	[ -b $W/loop.sqfs ] && { losetup -d $W/loop.sqfs; rm -f $W/loop.sqfs; }
	if [ -n "$USERSTORE" ]; then
		us_sys_done $ok || return 1
		rm -f $I $B/images/system.mb && sync
	else
		[ $ok = 0 ] || { rm -rf $S/rootfs.new; echo "cannot unpack"; return 1; }
		while grep -q " $R " /proc/mounts; do umount -l $R || break; done
		rm -rf $S/rootfs && mv $S/rootfs.new $S/rootfs && rm -f $I $B/images/system.mb && sync || return 1
	fi
	t "system unpacked"
	rmdir $B/images 2>/dev/null
}

prepare_files() {
	unpack_images || return 1
	for f in $S/rootfs/init $BIN/fbink $BIN/slirp4netns $BIN/pivot_init; do
		[ -e $f ] || { echo "missing $f"; return 1; }
	done
	mkdir -p $X $B/apps $S/data
}

mount_images() {
	if [ ! -x $R/pivot_init ]; then
		cp $BIN/pivot_init $R/pivot_init && chmod 755 $R/pivot_init || return 1
	fi
	if [ -n "$USERSTORE" ]; then
		mount -o remount,ro $R || return 1
	else
		grep -q " $R " /proc/mounts || { mount --bind $R $R && mount -o remount,ro,bind $R; } || return 1
	fi
	ip=$(ifconfig wlan0 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p')
	rm -f $W/cmdline
	echo "androidboot.hardware=kindle androidboot.zygote=zygote32 androidboot.wifiip=${ip:-off}$(hostnet_args)" > $W/cmdline
	chmod 644 $W/cmdline
	t "wifi ip ${ip:-off}"
}
