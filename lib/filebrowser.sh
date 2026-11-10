# 可选。把 linux-armv7 的 filebrowser 放进 bin/，设置 FILEBROWSER=1。
# 以 1023 跑，和安卓存储的属主一致。密码随机，只给桌面包的属主读。
FB_PORT=8080

filebrowser_apply() {
	p=$(cat $W/filebrowser.pid 2>/dev/null)
	if [ "$FILEBROWSER" != 1 ]; then
		[ -n "$p" ] && kill $p 2>/dev/null
		rm -f $W/filebrowser.pid
		for m in $(cat $W/fb.mounts 2>/dev/null); do umount -l $m; done
		rm -f $W/fb.mounts
		iptables -D INPUT -p tcp --dport $FB_PORT -j ACCEPT 2>/dev/null
		st=off
	elif [ ! -x $BIN/filebrowser ]; then
		st=missing
	else
		if [ -z "$p" ] || ! kill -0 $p 2>/dev/null; then
			db=$S/filebrowser.db
			k='exec env HOME="$0" chpst -u 1023:1023 "$@"'
			kp=
			command -v keyctl >/dev/null && k="keyctl link @us @s >/dev/null 2>&1; $k" && kp="keyctl session -"
			FB=$W/fbroot
			mkdir -p $FB
			grep -q " $FB " /proc/mounts || { mount -o rbind $S $FB && echo $FB >> $W/fb.mounts; }
			for m in $SHARE_DIRS ${B##*/}/apps:Apps ${B##*/}/icons:Icons ${B##*/}/screensaver:Screensaver; do
				kd=$U/${m%%:*}
				a=$FB/data/media/0/${m#*:}
				[ -d $kd ] && ! grep -q " $a " /proc/mounts && mkdir -p $a && mount --bind $kd $a && echo $a >> $W/fb.mounts
			done
			if [ ! -f $db ]; then
				pw=$(tr -dc a-z0-9 < /dev/urandom | head -c 12)
				touch $db
				chown 1023:1023 $db 2>/dev/null
				$kp sh -c "$k" $W $BIN/filebrowser -d $FB/filebrowser.db config init \
					--locale zh-cn --root $FB/data/media/0 --fileMode 0644 --dirMode 0755 >/dev/null 2>&1 &&
					$kp sh -c "$k" $W $BIN/filebrowser -d $FB/filebrowser.db users add kindle $pw --perm.admin >/dev/null 2>&1 &&
					echo $pw > $S/filebrowser.pw || rm -f $db
			fi
			rm -f $W/filebrowser.pid
			if [ -f $db ]; then
				setsid $kp sh -c "$k" $W $BIN/filebrowser -d $FB/filebrowser.db -a 0.0.0.0 -p $FB_PORT -r $FB/data/media/0 \
					</dev/null >$W/filebrowser.log 2>&1 &
				echo $! > $W/filebrowser.pid
			fi
			iptables -C INPUT -p tcp --dport $FB_PORT -j ACCEPT 2>/dev/null ||
				{ iptables -I INPUT -p tcp --dport $FB_PORT -j ACCEPT 2>/dev/null && echo $FB_PORT >> $W/lan.fw; }
			i=0
			until grep -q "Listening on" $W/filebrowser.log 2>/dev/null ||
				! kill -0 $(cat $W/filebrowser.pid 2>/dev/null) 2>/dev/null || [ $i -ge 20 ]; do
				usleep 500000
				i=$((i + 1))
			done
		fi
		ip=$(ifconfig wlan0 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p')
		kill -0 $(cat $W/filebrowser.pid 2>/dev/null) 2>/dev/null &&
			grep -q "Listening on" $W/filebrowser.log 2>/dev/null &&
			st="on http://${ip:-?}:$FB_PORT/" || st=error
	fi
	echo "$st" > $X/filebrowser
	chmod 644 $X/filebrowser
	rm -f $X/filebrowser.pw
	hu=$(stat -c %u $S/data/data/com.kindle.home 2>/dev/null)
	[ -n "$hu" ] && [ -f $S/filebrowser.pw ] && cp $S/filebrowser.pw $X/filebrowser.pw &&
		chown $hu $X/filebrowser.pw && chmod 400 $X/filebrowser.pw
	t "filebrowser: $st"
}
