# 设置页写出来的文件不 source。键在白名单里、值是页面能给出的那些，才赋值。

SETTINGS_KEYS="PAGE_ANIM KFB_ANIM_STEPS KFB_CONTRAST KFB_DITHER KFB_LOCAL_WFM KFB_COLOR KFB_FULL_EVERY KFB_TURN_WFM APP_DISPLAY KFB_GESTURES G_TAP G_HOLD G_HSWIPE G_VL G_VR
G_TL G_TR G_BL G_BR G_WINDOW G_CORNER_MS RETURN_MODE KINDLE_UI AUDIO ZRAM_MB ANDROID_DNS LAN_PORTS SHARE_DIRS FILEBROWSER SYS_FONT WEBVIEW_NEW"
GESTURE_ACTIONS="none clear invert back home switch menu light wifi sleep exit bt panel"

setting_ok() {
	case $1=$2 in
	PAGE_ANIM=hw | PAGE_ANIM=off | KFB_ANIM_STEPS=4 | KFB_ANIM_STEPS=8 | KFB_ANIM_STEPS=12 | KFB_ANIM_STEPS=16 | KFB_ANIM_STEPS=24) ;;
	KFB_CONTRAST=1.[0-9] | KFB_CONTRAST=2.[0-5] | KFB_DITHER=[01] | KFB_COLOR=[01] | KFB_GESTURES=[01] | AUDIO=[01] | FILEBROWSER=[01] | WEBVIEW_NEW=[01]) ;;
	RETURN_MODE=freeze | RETURN_MODE=off | KINDLE_UI=normal | KINDLE_UI=nofw) ;;
	LOWMEM=auto | LOWMEM=[01]) ;;
	KFB_LOCAL_WFM=du | KFB_LOCAL_WFM=a2 | KFB_LOCAL_WFM=auto) ;;
	KFB_FULL_EVERY=0 | KFB_FULL_EVERY=1 | KFB_FULL_EVERY=3 | KFB_FULL_EVERY=6 | KFB_FULL_EVERY=10 | KFB_FULL_EVERY=20 | KFB_TURN_WFM=reagl | KFB_TURN_WFM=gc16 | KFB_TURN_WFM=du) ;;
	APP_DISPLAY=*)
		case $2 in *[!A-Za-z0-9._,\ -]*) return 1 ;; esac
		for e in $2; do
			IFS=, read -r sd_p sd_a sd_c sd_f sd_w sd_x <<EOF
$e
EOF
			case $sd_p in [A-Za-z]*.*) ;; *) return 1 ;; esac
			[ -z "$sd_x" ] && { [ "$sd_a" = - ] || setting_ok PAGE_ANIM "$sd_a"; } &&
				{ [ "$sd_c" = - ] || setting_ok KFB_CONTRAST "$sd_c"; } &&
				{ [ "$sd_f" = - ] || setting_ok KFB_FULL_EVERY "$sd_f"; } &&
				{ [ "$sd_w" = - ] || setting_ok KFB_TURN_WFM "$sd_w"; } || return 1
		done ;;
	G_VL=none | G_VL=light | G_VL=warmth | G_VR=none | G_VR=light | G_VR=warmth) ;;
	G_TAP=?* | G_HOLD=?* | G_HSWIPE=?* | G_TL=?* | G_TR=?* | G_BL=?* | G_BR=?*)
		case " $GESTURE_ACTIONS " in *" $2 "*) ;; *) return 1 ;; esac ;;
	G_WINDOW=30 | G_WINDOW=50 | G_WINDOW=80 | G_WINDOW=100 | G_WINDOW=150 | G_CORNER_MS=500 | G_CORNER_MS=1000 | G_CORNER_MS=2000) ;;
	ZRAM_MB=0 | ZRAM_MB=256 | ZRAM_MB=384 | ZRAM_MB=512 | ZRAM_MB=768) ;;
	SYS_FONT=*) case $2 in */* | .*) return 1 ;; *.[Tt][Tt][Ff] | *.[Oo][Tt][Ff]) ;; *) return 1 ;; esac ;;
	ANDROID_DNS=*) case $2 in *[!0-9.\ ]*) return 1 ;; esac ;;
	LAN_PORTS=*)
		case $2 in *[!0-9\ ]*) return 1 ;; esac
		for p in $2; do [ ${#p} -le 5 ] && [ $p -ge 1 ] && [ $p -le 65535 ] || return 1; done ;;
	SHARE_DIRS=*)
		case $2 in *[!A-Za-z0-9._:\ -]*) return 1 ;; esac
		for m in $2; do
			case $m in .* | :* | *:*:*) return 1 ;; *:Books | *:Fonts | *:Download | *:Documents | *:Pictures | *:Music) ;; *) return 1 ;; esac
		done ;;
	*) return 1 ;;
	esac
}

settings_load() {
	[ -f $S/settings.conf ] && while IFS='=' read -r k v; do
		if setting_ok "$k" "$v"; then eval "$k=\$v"; else t "setting ignored: $k"; fi
	done < $S/settings.conf
	[ "$RETURN_MODE" = off ] && FREEZE=0 || FREEZE=1
	lowmem_detect
	command -v android_freeze >/dev/null || FREEZE=0
}

settings_export() {
	vs=
	warm_get >/dev/null 2>&1 && warm=1 || { warm=0; vs='s/^\(G_V[LR]\)=warmth$/\1=light/'; }
	for k in $SETTINGS_KEYS; do eval "echo \"$k=\$$k\""; done | sed "$vs" > $X/settings.tmp && mv -f $X/settings.tmp $X/settings
	( . $D/lib/defaults.sh; for k in $SETTINGS_KEYS; do eval "echo \"$k=\$$k\""; done ) | sed "$vs" > $X/defaults
	{
		echo "name=$(device_label)"
		echo "firmware=$(firmware_version)"
		echo "version=$(cat $D/VERSION 2>/dev/null)"
		echo "warmth=$warm"
		echo "lowmem=$LOWMEM"
		echo "userstore=$([ -n "$USERSTORE" ] && echo 1 || echo 0)"
		echo "anim=$(page_anim_ok && echo 1 || echo 0)"
		echo "webview_alt=$(cat $R/system/kindle/webview-alt/version 2>/dev/null)"
		echo "color=$([ "$(cat /sys/class/graphics/fb0/bits_per_pixel 2>/dev/null)" = 32 ] && echo 1 || echo 0)"
		printf 'dirs='
		for d in $U/*/; do
			d=${d%/}; d=${d##*/}
			case $d in system | "${B##*/}" | .* | *[!A-Za-z0-9._-]*) ;; *) printf '%s ' "$d" ;; esac
		done
		echo
		printf 'fonts='
		for f in $U/fonts/*.[TtOo][Tt][Ff]; do [ -f "$f" ] && printf '%s/' "${f##*/}"; done
		echo
	} > $X/info
	[ -f $W/license.info ] && cp -f $W/license.info $X/license && chmod 644 $X/license
}

gestures_conf() {
	for g in "$G_TAP" "$G_HOLD" "$G_HSWIPE" "$G_TL" "$G_TR" "$G_BL" "$G_BR"; do
		i=0
		for a in $GESTURE_ACTIONS; do [ "$a" = "$g" ] && break; i=$((i + 1)); done
		printf '%d ' $i
	done
	for v in "$G_VL" "$G_VR"; do
		case $v in light) printf '1 ' ;; warmth) printf '2 ' ;; *) printf '0 ' ;; esac
	done
	echo "$G_WINDOW $G_CORNER_MS"
}

settings_save() {
	f=$X/ctl/settings.saving
	mv -f $X/ctl/settings.new $f || return
	while IFS='=' read -r k v; do
		if setting_ok "$k" "$v"; then echo "$k=$v"; fi
	done < $f > $S/settings.conf.tmp && mv -f $S/settings.conf.tmp $S/settings.conf
	rm -f $f
	. $D/lib/defaults.sh
	settings_load
	epd_conf > $X/epd.conf && app_confs && echo reload > $X/epd.fifo
	gestures_conf > $X/gestures
	if [ "$KFB_GESTURES" = 0 ]; then touch $X/ctl/nogestures; else rm -f $X/ctl/nogestures; fi
	settings_export
	filebrowser_apply
	t "settings saved"
}
