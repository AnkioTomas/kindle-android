# Kindle 没有 swap。运行期间用内核自带的 zram。退出不 swapoff：把页读回来要几十秒。
swap_header() {
	le32() {
		printf "\\$(printf %o $(($1 & 255)))\\$(printf %o $(($1 >> 8 & 255)))\\$(printf %o $(($1 >> 16 & 255)))\\$(printf %o $(($1 >> 24 & 255)))"
	}
	{ le32 1; le32 $(( $(cat /sys/block/${1##*/}/size) / 8 - 1 )); } |
		dd of=$1 bs=1 seek=1024 conv=notrunc 2>/dev/null &&
		printf SWAPSPACE2 | dd of=$1 bs=1 seek=4086 conv=notrunc 2>/dev/null
}

zram_on() {
	Z=/sys/block/zram0
	[ "${ZRAM_MB:-0}" -gt 0 ] && [ -e $Z/disksize ] || return 0
	if [ "$LOWMEM" = 1 ] && grep -q "^/dev/zram0 " /proc/swaps &&
		[ "$(cat $Z/disksize)" -lt $((ZRAM_MB << 20)) ]; then
		swapoff /dev/zram0 && echo 1 > $Z/reset
		t "lowmem: replaced existing zram0"
	fi
	if ! grep -q "^/dev/zram0 " /proc/swaps; then
		[ "$(cat $Z/disksize)" != 0 ] && ! grep -q "^/dev/zram0 " /proc/mounts && echo 1 > $Z/reset
		[ "$(cat $Z/disksize)" = 0 ] || { t "zram0 in use"; return 0; }
		echo ${ZRAM_MB}M > $Z/disksize &&
			{ mkswap /dev/zram0 || swap_header /dev/zram0; } >/dev/null 2>&1 &&
			{ swapon -p 100 /dev/zram0 || swapon /dev/zram0; } 2>/dev/null || {
			echo 1 > $Z/reset 2>/dev/null
			t "zram failed"
			return 0
		}
	fi
	echo "$(cat /proc/sys/vm/swappiness) $(cat /proc/sys/vm/page-cluster)" > $W/zram.state
	echo 100 > /proc/sys/vm/swappiness
	echo 0 > /proc/sys/vm/page-cluster
	t "zram ${ZRAM_MB}MB"
}

lowmem_protect() {
	for p in $(pidof $PROTECT_PROCS); do
		echo "$p $(cat /proc/$p/oom_score_adj)" >> $W/oom.saved
		echo -800 > /proc/$p/oom_score_adj
	done
}
