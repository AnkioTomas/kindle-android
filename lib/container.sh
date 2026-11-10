# unshare 出 mount/UTS/IPC/net/pid，再把安卓根拼好，交给 pivot_init。

keys_start() {
	rm -f $X/keys $W/keydev.path
	[ -e /dev/uinput ] && [ -x $BIN/keyinject ] || return 0
	mkfifo $X/keys || return 0
	chmod 666 $X/keys
	$BIN/keyinject $X/keys > $W/keydev.path &
	echo $! > $W/keyinject.pid
	i=0
	while [ ! -s $W/keydev.path ] && kill -0 $! 2>/dev/null && [ $i -lt 50 ]; do
		usleep 20000
		i=$((i + 1))
	done
}

container_start() {
	keys_start
	$UNSHARE -- sh "$0" --in-ns "$KFB_TOUCH" "$KFB_KEYS" "$KFB_FTAP" &
	UPID=$!
	P=
	for i in 1 2 3 4 5 6 7 8 9 10; do
		container_child $UPID
		[ -n "$P" ] && break
		usleep 200000
	done
	[ -n "$P" ] || { t "container did not start"; return 1; }
	echo "$P" > $W/pid
	readlink /proc/$P/ns/mnt > $W/mntns
	t "container unshare=$UPID init=$P"
}

run_in_ns() {
	mount --make-rprivate / 2>/dev/null
	mount -t tmpfs -o nosuid,mode=755 tmpfs "$R/dev" || exit 1
	for n in null zero full tty random urandom kmsg fuse uhid; do
		[ -e /dev/$n ] && touch "$R/dev/$n" && mount --bind /dev/$n "$R/dev/$n"
	done
	chmod 666 /dev/vndbinder 2>/dev/null
	touch "$R/dev/binder" && mount --bind /dev/vndbinder "$R/dev/binder" || exit 1
	touch "$R/dev/tun" && mount --bind /dev/net/tun "$R/dev/tun"
	mkdir -p "$R/dev/socket" "$R/dev/input" "$R/dev/kfb" "$R/dev/pts" "$R/dev/__properties__"
	[ -n "$1" ] && touch "$R/dev/input/event0" && mount --bind "$1" "$R/dev/input/event0"
	[ -n "$2" ] && touch "$R/dev/input/event1" && mount --bind "$2" "$R/dev/input/event1"
	[ -n "$3" ] && touch "$R/dev/input/event2" && mount --bind "$3" "$R/dev/input/event2"
	mount --bind "$X" "$R/dev/kfb"
	[ -e /dev/fb0 ] && touch "$R/dev/epd" && mount --bind /dev/fb0 "$R/dev/epd"
	mkdir -p "$R/dev/graphics"
	[ -e /dev/fb0 ] && touch "$R/dev/graphics/fb0" && mount --bind /dev/fb0 "$R/dev/graphics/fb0"
	ev=$(cat $W/keydev.path 2>/dev/null)
	if [ -n "$ev" ] && [ -e "$ev" ]; then
		touch "$R/dev/input/event3"
		mount --bind "$ev" "$R/dev/input/event3"
	fi
	mount -t devpts -o mode=620,ptmxmode=666,newinstance devpts "$R/dev/pts"
	ln -s pts/ptmx "$R/dev/ptmx"

	mount -t proc proc "$R/proc" || exit 1
	mount --bind "$W/cmdline" "$R/proc/cmdline" || exit 1
	mount --bind "$R/proc/sys/net" "$R/proc/sys/net"
	mount --rbind "$R/proc/sys" "$R/proc/sys" && mount -o remount,ro,bind "$R/proc/sys"
	f=vm/mmap_rnd_compat_bits
	[ -e /proc/sys/$f ] || f=vm/mmap_rnd_bits
	mount --bind /proc/sys/$f "$R/proc/sys/$f" && mount -o remount,rw,bind "$R/proc/sys/$f" || exit 1
	for f in sysrq-trigger cpu/alignment; do
		[ -e "$R/proc/$f" ] && mount --bind "$R/proc/$f" "$R/proc/$f" && mount -o remount,ro,bind "$R/proc/$f"
	done

	mount -t sysfs -o ro sysfs "$R/sys" || exit 1
	for d in sys/fs/bpf sys/fs/pstore sys/kernel/tracing sys/kernel/debug; do
		[ -d "$R/$d" ] && mount -t tmpfs -o ro,size=4k tmpfs "$R/$d"
	done
	mount --bind "$W/idc" "$R/system/usr/idc" || exit 1
	[ -d "$W/kl" ] && mount --bind "$W/kl" "$R/system/usr/keylayout"
	mount --bind "$W/libkindleshim.so" "$R/system/lib/libkindleshim.so" || exit 1
	mount --bind "$S/data" "$R/data" && mount -o remount,bind,nosuid,nodev,noatime "$R/data" || exit 1

	mkdir -p $B/icons
	for m in $SHARE_DIRS ${B##*/}/apps:Apps ${B##*/}/icons:Icons ${B##*/}/screensaver:Screensaver; do
		k=$U/${m%%:*}
		a=$R/data/media/0/${m#*:}
		mkdir -p "$k" || continue
		if [ -z "$USERSTORE" ]; then
			find "$k" \( ! -user 1023 -o ! -group 1023 \) -exec chown 1023:1023 {} + 2>/dev/null
		fi
		mkdir -p "$a" && mount --bind "$k" "$a"
	done
	a=$R/data/media/0/Apps
	grep -q " $a " /proc/mounts && mount -o remount,ro,bind "$a"

	f=$U/fonts/$SYS_FONT
	if [ -n "$SYS_FONT" ] && [ -f "$f" ]; then
		sed -e '/<family name="sans-serif">/,/<\/family>/{' -e '/<font /{' -e '/weight="400" style="normal"/!d' -e '}' -e '}' \
			"$R/system/etc/fonts.xml" > "$W/fonts.xml" &&
			mount --bind "$f" "$R/system/fonts/Roboto-Regular.ttf" &&
			mount --bind "$W/fonts.xml" "$R/system/etc/fonts.xml"
	fi

	mount -t tmpfs -o nosuid,nodev tmpfs "$R/cache" || exit 1
	flags=$R/system/etc/kindle-webview-flags
	alt=$R/system/kindle/webview-alt
	rm -f "$X/swiftshader"
	if [ "$WEBVIEW_NEW" = 1 ] && [ -f "$alt/webview.apk" ]; then
		mount --bind "$alt" "$R/system/app/webview" && touch "$X/swiftshader"
		flags=$alt/flags
	fi
	mkdir -p "$R/data/local/tmp"
	echo "_ $(cat $flags 2>/dev/null || echo --disable-gpu --disable-gpu-compositing)" > "$R/data/local/tmp/webview-command-line"
	chmod 755 "$R/data/local" "$R/data/local/tmp"
	chmod 644 "$R/data/local/tmp/webview-command-line"

	exec "$R/pivot_init" $PIVOT_OPTS "$R"
}
