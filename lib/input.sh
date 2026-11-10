# 触摸屏和翻页键直接 bind 进容器。IDC 告诉安卓这是触摸屏。

mt_touch() {
	for e in /sys/class/input/event*; do
		set -- $(cat $e/device/capabilities/abs 2>/dev/null)
		[ $# -ge 2 ] || continue
		eval "hi=\${$(($# - 1))}"
		[ $(( 0x$hi >> 21 & 1 )) = 1 ] && { echo /dev/input/${e##*/}; return; }
	done
}

touch_setup() {
	KFB_TOUCH=$([ -e /dev/input/touch ] && echo /dev/input/touch ||
		awk '/^N: Name=/ { m = tolower($0) ~ /touch|pt_mt|cyttsp|zforce|goodix|elan|focal|fts/ }
			m && /^H: Handlers=/ { for (i = 1; i <= NF; i++) if (match($i, /event[0-9]+$/)) { print "/dev/input/" substr($i, RSTART); exit } }' \
			/proc/bus/input/devices)
	[ -n "$KFB_TOUCH" ] || KFB_TOUCH=$(mt_touch)
	export KFB_TOUCH
	touch_keys
	t "screen ${viewWidth}x${viewHeight} touch $KFB_TOUCH keys ${KFB_KEYS:-none}"
	rm -rf $W/kl
	cp -r $R/system/usr/keylayout $W/kl
	touch_extra
	chmod -R a+rX $W/kl
	rm -rf $W/idc
	mkdir -p $W/idc
	cp $R/system/usr/idc/* $W/idc/ 2>/dev/null
	if [ -n "$KFB_TOUCH" ]; then
		dev=$(readlink -f $KFB_TOUCH)
		chmod 666 $dev
		info=$(awk -v ev=${dev##*/} '/^I:/ { i = $0 } /^N: Name=/ { n = $0 } /^H: Handlers=/ && $0 ~ ("[ =]" ev "( |$)") { print i; print n; exit }' /proc/bus/input/devices)
		name=$(echo "$info" | sed -n 's/^N: Name="\(.*\)"$/\1/p' | tr -c 'A-Za-z0-9._\n-' '_')
		vp=$(echo "$info" | sed -n 's/.*Vendor=\([0-9a-f]*\) Product=\([0-9a-f]*\).*/Vendor_\1_Product_\2/p')
		for f in $name ${vp%Vendor_0000_Product_0000}; do
			printf 'touch.deviceType = touchScreen\ntouch.orientationAware = 1\ndevice.internal = 1\n' > $W/idc/$f.idc
		done
	fi
	chmod 755 $W/idc
	chmod 644 $W/idc/* 2>/dev/null
}
