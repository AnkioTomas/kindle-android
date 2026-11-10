# 屏保。有 screensaver/ 里的图就随机一张，否则用系统锁屏图。透明 PNG 不清屏。

screensaver_show() {
	n=0
	img=
	for f in $B/screensaver/*.[pP][nN][gG] $B/screensaver/*.[jJ][pP][gG] $B/screensaver/*.[jJ][pP][eE][gG]; do
		[ -f "$f" ] && n=$((n + 1)) && eval "img$n=\$f"
	done
	[ $n -gt 0 ] || [ -z "$SS_SYS" ] || for f in $SS_SYS; do
		[ -f "$f" ] && n=$((n + 1)) && eval "img$n=\$f"
	done
	[ $n -gt 0 ] && eval "img=\$img$(( $(date +%s) % n + 1 ))"
	[ -f "$img" ] || return
	c=-c
	case "$img" in
		*.[pP][nN][gG])
			ctype=$(od -An -tu1 -j25 -N1 "$img" | tr -d " ")
			{ [ "$ctype" = 4 ] || [ "$ctype" = 6 ] || head -c 65536 "$img" | grep -q tRNS; } && c= ;;
	esac
	$BIN/fbink -q $c -f -g file="$img",halign=center,valign=center,w=-2,dither
}
