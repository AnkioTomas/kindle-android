# apps/ 里的 apk 开机后安装，成功就删掉。打开应用不走 am，往 ctl/app 写一行，桌面自己起。

booted() { [ "$(cns /system/bin/getprop sys.boot_completed 2>/dev/null)" = 1 ]; }

after_boot() {
	i=0
	while [ $i -lt 900 ] && [ "$(cat $W/pid 2>/dev/null)" = "$P" ] && ! booted; do
		sleep 1
		i=$((i + 1))
	done
	[ "$(cat $W/pid 2>/dev/null)" = "$P" ] || return
	[ "$AUDIO" = 1 ] && for s in mediacodec mediaextractor; do
		cns /system/bin/setprop ctl.start $s
	done
	cns /system/bin/logcat -b main,system,crash -G 512K 2>/dev/null
	booted || { t "boot not completed"; sh $D/stop.sh >/dev/null 2>&1; return; }
	PR=/proc/$P/root
	if [ ! -f $PR/data/local/settings.done ]; then
		$A 'for k in window_animation_scale transition_animation_scale animator_duration_scale; do settings put global $k 0; done
			settings put global captive_portal_mode 0
			settings put global captive_portal_detection_enabled 0
			settings put global captive_portal_http_url http://connect.rom.miui.com/generate_204
			settings put global captive_portal_https_url https://connect.rom.miui.com/generate_204
			settings put secure install_non_market_apps 1
			pm disable android.ext.services/.notification.Ranker' >/dev/null &&
			touch $PR/data/local/settings.done $PR/data/local/unknown-sources.done
	fi
	[ -f $PR/data/local/unknown-sources.done ] ||
		{ $A 'settings put secure install_non_market_apps 1' >/dev/null && touch $PR/data/local/unknown-sources.done; }
	[ -f $PR/data/local/home-storage.done ] ||
		{ $A 'pm grant com.kindle.home android.permission.READ_EXTERNAL_STORAGE' >/dev/null 2>&1 && touch $PR/data/local/home-storage.done; }
	if [ "$(cat $PR/data/local/lowmem 2>/dev/null)" != "$LOWMEM" ]; then
		$A "settings put global always_finish_activities $LOWMEM" >/dev/null && echo $LOWMEM > $PR/data/local/lowmem
	fi
	[ "$LOWMEM" = 1 ] && $A 'service call activity 51 i32 1' >/dev/null && t "lowmem: 1 background process"
	for apk in "$B"/apps/*.apk; do
		[ -f "$apk" ] || continue
		t "installing ${apk##*/}"
		touch $W/slowboot
		before=$(ls $PR/data/app 2>/dev/null)
		cp "$apk" $PR/data/local/tmp/app.apk
		if $A pm install -r -d -g /data/local/tmp/app.apk | grep -q Success; then
			pkg=
			for d in $(ls $PR/data/app); do
				echo "$before" | grep -qx "$d" || pkg=${d%-*}
			done
			t "installed ${pkg:-${apk##*/}}"
			rm -f "$apk"
		else
			t "install failed: ${apk##*/}"
		fi
		rm -f $PR/data/local/tmp/app.apk
	done
	t "boot completed"
	[ -n "$HOME_OPENS" ] || app_open
}

app_open() {
	echo "$ANDROID_APP" > $X/ctl/app.tmp && mv -f $X/ctl/app.tmp $X/ctl/app
	t "opened $ANDROID_APP"
}
