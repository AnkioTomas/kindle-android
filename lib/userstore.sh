# PW5 的用户分区是 FAT：不能执行、没有符号链接、插 USB 时整盘要交给电脑。
# 系统和 /data 各放一个 ext4 镜像，只在安卓运行时挂着。
USERSTORE_MB=2048
USERSTORE_MAX_MB=4095
USERSTORE_GROW_MB=1024
USERSTORE_LOW_MB=512
USERSTORE_SPARE_MB=256
USERSTORE_SYS_MB=640
FATLOOP_RA_KB=256

loopdev() { [ -b /dev/loop/$1 ] && echo /dev/loop/$1 || echo /dev/loop$1; }

fatloop_fast() {
	fl=$(grep " $U vfat " /proc/mounts | cut -d' ' -f1)
	fl=loop${fl##*/}
	[ -f /sys/block/$fl/loop/dio ] && [ -f $B/bin/loopdio ] || return 0
	cp $B/bin/loopdio $W/loopdio && chmod 755 $W/loopdio || return 0
	[ -f $W/loopdio.state ] || echo "$fl $(cat /sys/block/$fl/loop/dio) $(cat /sys/block/$fl/queue/read_ahead_kb)" > $W/loopdio.state
	echo $FATLOOP_RA_KB > /sys/block/$fl/queue/read_ahead_kb
	$W/loopdio $(loopdev ${fl#loop}) 1 2>/dev/null || t "userstore: no direct-io on $fl"
}

fatloop_restore() {
	[ -f $W/loopdio.state ] || return 0
	read fl dio ra < $W/loopdio.state
	[ -x $W/loopdio ] && $W/loopdio $(loopdev ${fl#loop}) $dio
	echo $ra > /sys/block/$fl/queue/read_ahead_kb
	rm -f $W/loopdio.state $W/loopdio
}

us_img_mb() { echo $(( $(stat -c %s $USERSTORE) / 1048576 )); }

us_fs_mb() {
	if grep -q " $S/data ext4 " /proc/mounts; then
		df -kP $S/data | awk 'NR==2 { printf "%d %d\n", $3 / 1024, $4 / 1024 }'
	else
		dumpe2fs -h $USERSTORE 2>/dev/null | awk -F: '/^Block count/ { c = $2 } /^Free blocks/ { f = $2 } /^Block size/ { b = $2 }
			END { printf "%d %d\n", (c - f) * b / 1048576, f * b / 1048576 }'
	fi
}

us_limits() {
	img=$(us_img_mb)
	set -- $(us_fs_mb)
	used=$1
	free=$2
	fat=$(df -kP $U | awk 'NR==2 { print int($4 / 1024) }')
	sys=$USERSTORE_SYS_MB
	[ -f $SYSIMG ] && sys=$(( $(stat -c %s $SYSIMG) / 1048576 ))
	max=$((img + fat - USERSTORE_SPARE_MB - sys))
	[ $max -gt $USERSTORE_MAX_MB ] && max=$USERSTORE_MAX_MB
	[ $max -lt $img ] && max=$img
	min=$(( (used + 512 + 255) / 256 * 256 ))
	[ $min -gt $img ] && min=$img
}

userstore_info() {
	[ -n "$USERSTORE" ] && [ -f $USERSTORE ] || return 0
	us_limits
	{ echo "img=$img"; echo "used=$used"; echo "free=$free"; echo "fat=$fat"
	  echo "max=$max"; echo "min=$min"
	  echo "pending=$(cat $B/userstore.resize 2>/dev/null)"
	} > $X/ctl/userstore.tmp && chmod 644 $X/ctl/userstore.tmp && mv -f $X/ctl/userstore.tmp $X/ctl/userstore
}

userstore_request() {
	[ -n "$USERSTORE" ] || return 0
	case "$1" in '' | *[!0-9]*) return 0 ;; esac
	us_limits
	if [ "$1" = 0 ] || [ "$1" = "$img" ]; then rm -f $B/userstore.resize
	elif [ "$1" -ge $min ] && [ "$1" -le $max ]; then echo "$1" > $B/userstore.resize; fi
}

us_say() {
	[ -x $W/fbink.us ] || { cp $B/bin/fbink $W/fbink.us 2>/dev/null && chmod 755 $W/fbink.us; }
	$W/fbink.us -q -c -m -M -t regular=/usr/java/lib/fonts/STHeitiMedium.ttf,px=40 "$1" 2>/dev/null
}

userstore_adjust() {
	us_limits
	to=$(cat $B/userstore.resize 2>/dev/null)
	rm -f $B/userstore.resize
	if [ -z "$to" ] && [ $free -lt $USERSTORE_LOW_MB ] && [ $img -lt $USERSTORE_MAX_MB ]; then
		to=$((img + USERSTORE_GROW_MB))
		[ $to -gt $max ] && to=$max
		[ $to -gt $img ] && t "userstore: auto grow, free $free MB"
	fi
	[ -n "$to" ] || return 0
	[ $to -gt $max ] && to=$max
	[ $to -lt $min ] && to=$min
	[ "$to" != $img ] || return 0
	if [ $to -gt $img ]; then
		us_say "正在扩大存储…"
		if dd if=/dev/zero of=$USERSTORE bs=1M seek=$img count=$((to - img)) conv=notrunc 2>/dev/null; then
			e2fsck -fy $USERSTORE >/dev/null 2>&1
			[ $? -le 1 ] && resize2fs $USERSTORE >/dev/null 2>&1 && { t "userstore: grown to $to MB"; return 0; }
		fi
		fs=$(dumpe2fs -h $USERSTORE 2>/dev/null | awk -F: '/^Block count/ { c = $2 } /^Block size/ { b = $2 } END { print int(c * b / 1048576) }')
		[ "${fs:-0}" -gt 0 ] && [ "$fs" -le $img ] && truncate -s $((img * 1048576)) $USERSTORE
		t "userstore: grow to $to MB failed"
	else
		us_say "正在缩小存储…"
		e2fsck -fy $USERSTORE >/dev/null 2>&1
		[ $? -le 1 ] || { t "userstore: e2fsck failed"; return 0; }
		resize2fs $USERSTORE ${to}M >/dev/null 2>&1 && truncate -s $((to * 1048576)) $USERSTORE && t "userstore: shrunk to $to MB"
	fi
}

us_mount() {
	mkdir -p $2 && loop_mount $1 $2 ext4 noatime || return 1
	d=$(awk -v s=$2 '$5 == s { print $3; exit }' /proc/self/mountinfo)
	case $d in
		7:*) [ -x $W/loopdio ] && $W/loopdio $(loopdev ${d#7:}) 1 2>/dev/null ;;
	esac
	[ -n "$d" ] && echo 128 > /sys/dev/block/$d/queue/read_ahead_kb
}

us_umount() {
	while grep -q " $1 " /proc/mounts; do umount $1 2>/dev/null || umount -l $1 || break; done
	l=$W/loop.${1##*/}
	[ -b $l ] && { losetup -d $l 2>/dev/null; rm -f $l; }
}

us_fb_copy() {
	[ -f $B/bin/filebrowser ] && [ -d $R/system ] || return 0
	mkdir -p $R/kindle-bin && chmod 755 $R/kindle-bin
	src=$(stat -c '%s %Y' $B/bin/filebrowser)
	[ -x $R/kindle-bin/filebrowser ] && [ "$(cat $R/kindle-bin/.src 2>/dev/null)" = "$src" ] ||
		{ cp $B/bin/filebrowser $R/kindle-bin/ && echo "$src" > $R/kindle-bin/.src; } || return 0
	chmod 755 $R/kindle-bin/filebrowser
	ln -sf $R/kindle-bin/filebrowser $BIN/filebrowser
}

userstore_setup() {
	grep -q " $U vfat " /proc/mounts || return 0
	USERSTORE=$S-data.img
	SYSIMG=$S-sys.img
	BIN=$W/bin
	fatloop_fast
	mkdir -p $BIN
	for f in $B/bin/*; do
		[ -f $f ] && [ "${f##*/}" != filebrowser ] && ! cmp -s $f $BIN/${f##*/} && cp $f $BIN/
	done
	for f in $BIN/*; do
		[ -e $f ] && [ ! -e $B/bin/${f##*/} ] && rm -f $f
	done
	chmod 755 $BIN/* 2>/dev/null
	[ -f $SYSIMG ] && ! grep -q " $R " /proc/mounts && { us_mount $SYSIMG $R || return 1; us_fb_copy; }
	if ! grep -q " $S/data " /proc/mounts; then
		[ -f $USERSTORE ] && userstore_adjust
		if [ ! -f $USERSTORE ]; then
			rm -f $USERSTORE.new
			mb=$(( $(df -kP $U | awk 'NR==2 { print int($4 / 1024) }') - USERSTORE_SPARE_MB ))
			[ -f $SYSIMG ] || mb=$((mb - USERSTORE_SYS_MB))
			[ $mb -gt $USERSTORE_MB ] && mb=$USERSTORE_MB
			mb=$((mb / 256 * 256))
			if [ $mb -lt 1024 ]; then
				us_say "Kindle 空间不够，至少要再留出 1GB"
				sleep 10
				return 1
			fi
			us_say "正在准备存储，第一次要一两分钟"
			dd if=/dev/zero of=$USERSTORE.new bs=1M count=$mb 2>/dev/null &&
				mke2fs -q -F -t ext4 -m 0 -L android-data -E lazy_itable_init=0,lazy_journal_init=0,nodiscard $USERSTORE.new &&
				mv $USERSTORE.new $USERSTORE || { rm -f $USERSTORE.new; return 1; }
		fi
		us_mount $USERSTORE $S/data || return 1
	fi
	t "userstore ready"
}

us_sys_size() {
	fb=$(du -sm $B/bin/filebrowser 2>/dev/null | cut -f1)
	echo $(( (($1 + ${fb:-0}) * 115 / 100 + 32 + 63) / 64 * 64 ))
}

us_sys_new() {
	rm -f $SYSIMG.new
	fat=$(df -kP $U | awk 'NR==2 { print int($4 / 1024) }')
	if [ $(( fat - USERSTORE_SPARE_MB )) -lt $1 ]; then
		us_say "空间不够，装系统要 $1 MB"
		sleep 10
		return 1
	fi
	dd if=/dev/zero of=$SYSIMG.new bs=1M count=$1 2>/dev/null &&
		mke2fs -q -F -t ext4 -m 0 -L android-sys -E lazy_itable_init=0,lazy_journal_init=0,nodiscard $SYSIMG.new &&
		us_mount $SYSIMG.new $W/sys.new || { us_umount $W/sys.new; rm -f $SYSIMG.new; return 1; }
}

us_sys_done() {
	us_umount $W/sys.new
	rmdir $W/sys.new 2>/dev/null
	[ "$1" = 0 ] || { rm -f $SYSIMG.new; return 1; }
	us_umount $R
	mv -f $SYSIMG.new $SYSIMG && sync && us_mount $SYSIMG $R && us_fb_copy
}
