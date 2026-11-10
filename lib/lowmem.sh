# 总内存不到 700MB（Paperwhite 5 这一档）时：不冻结、停掉整个 Kindle 界面、开机前丢掉页缓存。
# FAT 上的镜像退出时必须卸掉才能把 U 盘交给电脑，所以只要是 FAT 就不冻结。
lowmem_detect() {
	case $LOWMEM in
		1 | 0) ;;
		*) [ "$(awk '/^MemTotal/ { print $2 }' /proc/meminfo)" -lt 716800 ] && LOWMEM=1 || LOWMEM=0 ;;
	esac
	if [ "$LOWMEM" = 1 ]; then
		FREEZE=0
		KINDLE_UI=nofw
	fi
	[ -z "$USERSTORE" ] || FREEZE=0
}

lowmem_drop_caches() {
	[ "$LOWMEM" = 1 ] || return 0
	sync
	echo 3 > /proc/sys/vm/drop_caches
	t "lowmem: $(awk '/^MemAvailable/ { printf "%d", $2 / 1024 }' /proc/meminfo) MB free"
}
