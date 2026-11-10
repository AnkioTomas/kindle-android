# /dev/kfb：尺寸、波形、两个 FIFO、ctl/ 里的文件信号。兼容库和宿主只通过这里说话。
# epd.conf 三行：抖动 动画 步数 局部波形 彩色；256 个 gamma；隔几页全刷 整页波形。
# 波形编号是 MTK 的：DU 1，GC16 2，REAGL 4，A2 6，AUTO 257。

detect_screen() {
	eval "$($BIN/fbink -e 2>/dev/null)"
	[ -n "$viewWidth" ] || { t "fbink -e failed"; return 1; }
}

epd_conf() {
	case "$KFB_LOCAL_WFM" in
		du | DU) wfm=1 ;;
		a2 | A2) wfm=6 ;;
		*) wfm=257 ;;
	esac
	echo "${KFB_DITHER:-1} $({ [ "$PAGE_ANIM" = off ] || ! page_anim_ok; } && echo 0 || echo 1) ${KFB_ANIM_STEPS:-12} $wfm ${KFB_COLOR:-1}"
	awk -v g="${KFB_CONTRAST:-1}" 'BEGIN { g += 0; if (g < 1) g = 1; if (g > 2.5) g = 2.5
		for (i = 0; i < 256; i++) printf "%d%s", int((i / 255) ^ g * 255 + 0.5), i < 255 ? " " : "\n" }'
	case "$KFB_TURN_WFM" in
		gc16) wfm=2 ;;
		du) wfm=1 ;;
		*) wfm=4 ;;
	esac
	echo "${KFB_FULL_EVERY:-0} $wfm"
}

app_confs() {
	rm -f $X/epd.conf.*
	for e in $APP_DISPLAY; do
		IFS=, read -r ad_p ad_a ad_c ad_f ad_w <<EOF
$e
EOF
		( [ "$ad_a" = - ] || PAGE_ANIM=$ad_a
		  [ "$ad_c" = - ] || KFB_CONTRAST=$ad_c
		  [ "$ad_f" = - ] || KFB_FULL_EVERY=$ad_f
		  [ "$ad_w" = - ] || KFB_TURN_WFM=$ad_w
		  epd_conf ) > $X/epd.conf.$ad_p
		chmod 644 $X/epd.conf.$ad_p
	done
}

note() {
	[ -n "$np" ] && kill $np 2>/dev/null
	( px=$((viewHeight / 40)) w=$((viewWidth * 2 / 5)) h=$((viewHeight / 14)) b=$((viewHeight / 600 + 2))
	  l=$(((viewWidth - w) / 2)) tp=$((viewHeight * 45 / 100))
	  $BIN/fbink -q -b -B BLACK -k top=$tp,left=$l,width=$w,height=$h
	  $BIN/fbink -q -b -k top=$((tp + b)),left=$((l + b)),width=$((w - 2 * b)),height=$((h - 2 * b))
	  $BIN/fbink -q -b -O -m -t regular=$KFONT,px=$px,top=$((tp + (h - px * 3 / 2) / 2)),left=$((l + b)),right=$((viewWidth - l - w + b)) "$1"
	  $BIN/fbink -q -s top=$tp,left=$l,width=$w,height=$h
	  sleep 2
	  echo "rows $tp $((tp + h))" > $X/epd.fifo ) &
	np=$!
}

kfb_ctl() {
	fl=
	am=
	while read -r c; do
		case "$c" in
		touch) idle_touch ;;
		cmd:suspend) host_suspend ;;
		cmd:fl_step=*)
			fl=$(( ${fl:-$(fl_get 2>/dev/null || echo 10)} ${c#*=} ))
			[ $fl -lt 0 ] && fl=0
			[ $fl -gt 24 ] && fl=24
			fl_set $fl && note "亮度 $fl" ;;
		cmd:warmth_step=*)
			am=$(( ${am:-$(warm_get 2>/dev/null || echo 0)} ${c#*=} ))
			[ $am -lt 0 ] && am=0
			[ $am -gt 24 ] && am=24
			warm_set $am && note "色温 $am" ;;
		cmd:fl_set=* | cmd:warmth_set=*)
			v=${c#*=}
			case $v in '' | *[!0-9]*) continue ;; esac
			[ $v -gt 24 ] && v=24
			case $c in
				cmd:fl*) fl=$v; fl_set $v ;;
				*) am=$v; warm_set $v ;;
			esac ;;
		cmd:status)
			sb=
			for p in /sys/class/power_supply/*; do
				[ "$(cat $p/type 2>/dev/null)" = Battery ] && [ -f $p/capacity ] && sb=$p && break
			done
			IFS='|' read -r sh_t sh_d sh_w <<EOF
$(date '+%H:%M|%Y年%-m月%-d日|%w')
EOF
			{ if [ -n "$sb" ]; then
				echo "batt=$(cat $sb/capacity)"
				echo "charging=$([ "$(cat $sb/status)" = Charging ] && echo 1 || echo 0)"
			  else platform_battery; fi
			  echo "time=$sh_t"
			  echo "date=$sh_d"
			  echo "week=$sh_w"
			  echo "wifi=$(wifi_get)"
			  echo "essid=$(iwconfig wlan0 2>/dev/null | sed -n 's/.*ESSID:"\(.*\)".*/\1/p')"
			  echo "fl=$(fl_get)"
			  echo "warm=$(warm_get)"
			  platform_status
			  echo "inv=$([ -f $X/ctl/invert ] && echo 1 || echo 0)"
			} > $X/ctl/status.tmp 2>/dev/null && chmod 644 $X/ctl/status.tmp && mv -f $X/ctl/status.tmp $X/ctl/status ;;
		cmd:userstore) userstore_info ;;
		cmd:userstore_resize=*) userstore_request "${c#*=}"; userstore_info ;;
		cmd:fl_toggle)
			c=$(fl_get 2>/dev/null || echo 0)
			if [ "$c" -gt 0 ]; then flo=$c; fl=0; else fl=${flo:-10}; fi
			fl_set $fl && { [ $fl = 0 ] && note "前光已关闭" || note "前光已打开"; } ;;
		*) platform_cmd "$c" ;;
		esac >/dev/null 2>&1
	done
}

display_start() {
	mountpoint -q $X || mount -t tmpfs -o size=1m,mode=755 tmpfs $X
	rm -f $X/kfb.fifo $X/epd.fifo $X/audio.fifo
	mkfifo $X/kfb.fifo $X/epd.fifo
	[ "$AUDIO" = 1 ] && mkfifo -m 666 $X/audio.fifo
	echo "$viewWidth $viewHeight" > $X/geom
	epd_conf > $X/epd.conf
	app_confs
	chmod 666 $X/kfb.fifo $X/epd.fifo /dev/fb0
	chmod 644 $X/geom $X/epd.conf
	rm -rf $X/ctl
	mkdir -p $X/ctl
	chmod 777 $X/ctl
	[ "$KFB_GESTURES" = 0 ] && touch $X/ctl/nogestures
	display_extra
	gestures_conf > $X/gestures
	settings_export
	chmod 644 $X/gestures $X/settings $X/defaults $X/info
	warm_get >/dev/null 2>&1 && touch $X/ctl/warmth
	[ -f $S/invert ] && touch $X/ctl/invert
	splash
	sleep 2147483647 <> $X/kfb.fifo 3<> $X/epd.fifo &
	echo $! > $W/kfbhold.pid
	kfb_ctl < $X/kfb.fifo &
	echo $! > $W/kfb.pid
}

ms_now() { awk '{ printf "%d", $1 * 1000 }' /proc/uptime; }

splash_text() {
	case "$ANDROID_APP" in
		com.tencent.weread*) name=微信读书 ;;
		com.duokan*) name=多看阅读 ;;
		*) name=Android ;;
	esac
	top=$((viewHeight * 36 / 100))
	$BIN/fbink -q -m -t regular=$KFONT,px=$((viewHeight / 22)),top=$top "$name" 2>/dev/null &&
		$BIN/fbink -q -m -t regular=$KFONT,px=$((viewHeight / 45)),top=$((top + viewHeight / 11)) "${2:-正在启动…}" 2>/dev/null
}

splash() {
	rm -f $X/ctl/shown $W/slowboot
	if [ -n "$INSTALLED" ]; then $BIN/fbink -q -y -10 -P 0
	else $BIN/fbink -q -c -f " "; fi
	splash_text
	est=$(cat $S/startup.ms 2>/dev/null)
	[ "${est:-0}" -gt 3000 ] 2>/dev/null || est=60000
	t0=$(ms_now)
	(
		i=0
		sb=
		while [ ! -f $X/ctl/shown ] && { [ -f $W/pid ] || [ $i -lt 30 ]; } && [ $i -lt 900 ]; do
			pct=$(( ($(ms_now) - t0) * 100 / est ))
			[ $pct -gt 95 ] && pct=95
			[ $i -lt 4 ] && splash_text
			[ -z "$sb" ] && [ -f $W/slowboot ] && sb=1 && splash_text "" "正在安装应用…"
			$BIN/fbink -q -y -10 -P $pct
			sleep 1
			i=$((i + 1))
		done
		[ -f $W/pid ] && [ -f $X/ctl/shown ] || exit 0
		el=$(( $(ms_now) - t0 ))
		[ -f $W/slowboot ] || echo $el > $S/startup.ms
		t "first frame ${el}ms"
	) &
}
