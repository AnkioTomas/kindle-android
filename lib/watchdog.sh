diag_save() {
	n=Diagnostics/$(date +%Y%m%d-%H%M%S)
	o=$S/data/media/0/$n
	mkdir -p $o
	$A "cd /data/media/0/$n && logcat -d -v threadtime -b main,system,crash > logcat.txt
		logcat -d -b crash > crash.txt
		dumpsys meminfo > meminfo.txt
		getprop > props.txt
		cp -r /data/tombstones /data/anr . 2>/dev/null" >/dev/null 2>&1
	cp $S/android.log $S/settings.conf $o/ 2>/dev/null
	dmesg > $o/dmesg.txt
	cat /proc/meminfo > $o/kindle-meminfo.txt
	ps > $o/kindle-ps.txt
	chown -R 1023:1023 $S/data/media/0/Diagnostics 2>/dev/null
	echo $n > $X/ctl/diag.done
	t "diag saved: $n"
}

stop_android() { exec >/dev/null 2>&1; sh $D/stop.sh; }

watchdog() {
	while sleep 2; do
		kill -0 $P 2>/dev/null || { t "android exited"; stop_android; break; }
		if [ -f $X/ctl/stop ]; then
			t "stop requested"
			stop_android
			break
		fi
		if [ -f $X/ctl/restart ]; then
			t "restart requested"
			touch $W/restarting
			stop_android
			sh $D/android.sh home </dev/null >/dev/null 2>&1 &
			break
		fi
		if [ -f $X/ctl/diag ]; then rm -f $X/ctl/diag; diag_save & fi
		[ -f $X/ctl/settings.new ] && settings_save
		if [ -f $X/ctl/exit ]; then
			t "exit requested"
			if [ "$FREEZE" = 1 ] && [ -d "$FZ" ]; then android_freeze
			else stop_android; fi
			break
		fi
	done
}
