# Kindle 宿主。lib/ 只调这里的函数，不写 lipc。

platform_init() {
	BOURBON=
	unshare -n true >/dev/null 2>&1 || BOURBON=1
}
PROTECT_PROCS="powerd lipcd dropbear sshd wifid wpa_supplicant"
SS_SYS="/usr/share/blanket/screensaver/bg_ss*.png"
KFONT=/usr/java/lib/fonts/STHeitiMedium.ttf
NET=10.157.43
UNSHARE="unshare -m -u -i -n -p -f"
PIVOT_OPTS=
SERVICES="mtp stored webreader kfxreader kfxview todo tmd rcm archive scanner"
[ -f /etc/upstart/statusbar.conf ] && SERVICES="$SERVICES statusbar"
LOWMEM_SERVICES="fastmetrics platformmetricsd phd dynconfig battstressd stackdumpd acedropboxd ace_eventmgr
	ace_messaging_service whisperstore contentpackd poll_daemons progressivedownloads juno-acs-helper
	ttsorchestrator playermgr playermgr_limit kb logmgr"

page_anim_ok() { case "$deviceName" in "Basic 4"*) return 1 ;; esac; return 0; }

kindle_home() {
	if [ -f /etc/upstart/kppmainapp.conf ]; then
		i=0
		command -v lipc-probe >/dev/null && until lipc-probe com.lab126.KPPMainApp 2>/dev/null | grep -qw go || [ $i -ge 60 ]; do
			sleep 2
			i=$((i + 1))
		done
		u="app://com.lab126.KPPMainApp?view=KPP_HOME"
	else
		u=app://com.lab126.booklet.home
	fi
	lipc-set-prop com.lab126.appmgrd start "$u" 2>/dev/null
}

fb_screen() {
	F=/sys/class/graphics/fb0
	echo "$(cat $F/stride) $(cut -d, -f2 $F/pan) $(sed -n 's/.*x\([0-9]*\)p.*/\1/p' $F/modes | head -1)"
}

usb_storage_off() {
	for u in /sys/class/udc/*; do
		[ -e $u/device/gadget/lun0 ] && echo disconnect > $u/soft_connect && touch $W/usb.off
	done
}
usb_storage_on() {
	[ -f $W/usb.off ] || return 0
	for u in /sys/class/udc/*; do echo connect > $u/soft_connect; done
	rm -f $W/usb.off
}

landscape() {
	IFS=, read -r vw vh < /sys/class/graphics/fb0/virtual_size
	[ "$vw" -gt $((vh / 2)) ]
}

framework_stop() {
	if [ -f $W/restarting ]; then
		rm -f $W/restarting
		m=normal
		[ -f $W/nofw ] && m=nofw
		if [ -f $W/ui.frozen ] && [ "$m" = "${KINDLE_UI:-normal}" ]; then
			t "restart: ui still frozen"
			return
		fi
		if [ -f $W/ui.frozen ]; then
			framework_start
			p=$(cat $W/fwstart.pid 2>/dev/null)
			i=0
			while [ -n "$p" ] && kill -0 $p 2>/dev/null && [ $i -lt 120 ]; do
				sleep 1
				i=$((i + 1))
			done
		fi
	fi
	if [ "$KINDLE_UI" = nofw ]; then
		lipc-set-prop -s com.lab126.blanket unload splash 2>/dev/null
		lipc-set-prop -s com.lab126.blanket unload screensaver 2>/dev/null
		stop lab126_gui >/dev/null 2>&1
		cp $BIN/kafstub $W/kafstub && chmod 755 $W/kafstub
		setsid $W/kafstub </dev/null >/dev/null 2>&1 &
		echo $! > $W/kafstub.pid
		killall -STOP volumd 2>/dev/null
		usb_storage_off
		touch $W/ui.frozen $W/nofw
		lowmem_protect
	else
		set -- $(fb_screen)
		dd if=/dev/fb0 of=$S/kindle-screen.raw bs=$1 skip=$2 count=$3 2>/dev/null
		lipc-set-prop com.lab126.pillow disableEnablePillow disable 2>/dev/null
		killall -STOP awesome volumd 2>/dev/null
		usb_storage_off
		DISPLAY=:0 xinput disable kindle-input-pt 2>/dev/null
		DISPLAY=:0 xinput disable gesture_tap 2>/dev/null
		touch $W/ui.frozen
	fi
	F=/sys/class/graphics/fb0
	if [ -w $F/rotate ] && landscape; then
		r=$(cat $F/rotate)
		[ -f $W/fb.rotate ] || echo $r > $W/fb.rotate
		case "$($BIN/fbink -e 2>/dev/null | tr ';' '\n' | sed -n "s/^deviceName='\(.*\)'$/\1/p")" in
			Scribe*) up=1 ;;
			"Basic 5"*) up=3 ;;
			"PaperWhite 6"* | [Cc]olor[Ss]oft*) up=0 ;;
			*) up=$((r ^ 1)) ;;
		esac
		echo $up > $F/rotate
		landscape && echo $((r ^ 1)) > $F/rotate
		t "rotated $r -> $(cat $F/rotate)"
	fi
	[ -f $W/core_pattern ] || cat /proc/sys/kernel/core_pattern > $W/core_pattern
	echo "|/bin/true" > /proc/sys/kernel/core_pattern
	kill $(cat $W/fwstart.pid 2>/dev/null) 2>/dev/null
	rm -f $W/fwstart.pid
	( for s in $SERVICES $([ "$LOWMEM" = 1 ] && echo $LOWMEM_SERVICES); do
		initctl status $s 2>/dev/null | grep -q start/ && { echo $s >> $W/services.stopped; stop $s >/dev/null 2>&1; }
	  done
	  rm -f $W/fwstop.pid ) &
	echo $! > $W/fwstop.pid
	t "kindle ui frozen"
}

framework_start() {
	[ -f $W/ui.frozen ] || return
	rm -f $W/ui.frozen
	[ -f $W/fb.rotate ] && cat $W/fb.rotate > /sys/class/graphics/fb0/rotate
	rm -f $W/fb.rotate
	kill $(cat $W/fwstop.pid 2>/dev/null) 2>/dev/null
	rm -f $W/fwstop.pid
	[ -f $W/oom.saved ] && while read -r p v; do echo $v > /proc/$p/oom_score_adj; done < $W/oom.saved 2>/dev/null
	rm -f $W/oom.saved
	if [ -f $W/nofw ]; then
		rm -f $W/nofw
		kill $(cat $W/kafstub.pid 2>/dev/null) 2>/dev/null
		rm -f $W/kafstub.pid
		killall -CONT volumd 2>/dev/null
		usb_storage_on
		d=$(cd "$(dirname "$0")" && pwd)
		${BIN:-$d/bin}/fbink -q -c -m -M -t regular=$KFONT,px=48 "正在返回 Kindle…" 2>/dev/null
		( sleep 2; i=0; while [ $i -lt 40 ]; do lipc-send-event com.lab126.bootactions bootActionsReady 2>/dev/null; usleep 250000; i=$((i + 1)); done ) &
		( sleep 2
		  start lab126_gui >/dev/null 2>&1
		  kindle_home
		  lipc-set-prop -s com.lab126.blanket load screensaver 2>/dev/null
		  for s in $(cat $W/services.stopped 2>/dev/null); do start $s >/dev/null 2>&1; done
		  rm -f $W/services.stopped
		  [ -f $W/core_pattern ] && cat $W/core_pattern > /proc/sys/kernel/core_pattern && rm -f $W/core_pattern
		  rm -f $W/fwstart.pid ) &
		echo $! > $W/fwstart.pid
		return
	fi
	set -- $(fb_screen)
	[ -f $S/kindle-screen.raw ] && dd if=$S/kindle-screen.raw of=/dev/fb0 bs=$1 seek=$2 count=$3 2>/dev/null
	${BIN:-"$(cd "$(dirname "$0")" && pwd)/bin"}/fbink -q -s 2>/dev/null
	DISPLAY=:0 xinput enable kindle-input-pt 2>/dev/null
	DISPLAY=:0 xinput enable gesture_tap 2>/dev/null
	killall -CONT awesome volumd 2>/dev/null
	usb_storage_on
	lipc-set-prop com.lab126.pillow disableEnablePillow enable 2>/dev/null
	kindle_home
	( for s in $(cat $W/services.stopped 2>/dev/null); do start $s >/dev/null 2>&1; done
	  rm -f $W/services.stopped
	  [ -f $W/core_pattern ] && cat $W/core_pattern > /proc/sys/kernel/core_pattern && rm -f $W/core_pattern
	  sleep 20
	  initctl status framework 2>/dev/null | grep -q running || start lab126_gui
	  rm -f $W/fwstart.pid ) &
	echo $! > $W/fwstart.pid
}

fl_get() { lipc-get-prop com.lab126.powerd flIntensity; }
fl_set() { lipc-set-prop -i com.lab126.powerd flIntensity $1; }
warm_get() { lipc-get-prop com.lab126.powerd currentAmberLevel; }
warm_set() { lipc-set-prop -i com.lab126.powerd currentAmberLevel $1; }
idle_touch() { lipc-set-prop -i com.lab126.powerd touchScreenSaverTimeout 1; }
host_suspend() { lipc-set-prop -i com.lab126.powerd powerButton 1; }
wifi_get() { lipc-get-prop com.lab126.cmd wirelessEnable; }

platform_cmd() {
	c=$1
	case "$c" in
	cmd:fl_auto=0 | cmd:fl_auto=1)
		lipc-set-prop -i com.lab126.powerd flAuto ${c#*=}
		fl= ;;
	audio)
		[ -n "$ap" ] && kill -0 $ap 2>/dev/null || {
			if command -v gst-launch-1.0 >/dev/null; then
				gst-launch-1.0 -q fdsrc fd=0 ! rawaudioparse format=pcm pcm-format=s16le sample-rate=44100 num-channels=2 ! mixersink < $X/audio.fifo &
			else
				gst-launch-0.10 -q fdsrc fd=0 ! audio/x-raw-int,endianness=1234,signed=true,width=16,depth=16,rate=44100,channels=2 ! mixersink < $X/audio.fifo &
			fi
			ap=$!
		} ;;
	cmd:bt_toggle)
		if [ "$(lipc-get-prop com.lab126.btfd BTstate 2>/dev/null || echo 0)" != 0 ]; then
			lipc-set-prop -i com.lab126.btfd BTflightMode 1 && note "蓝牙已关闭"
		else
			lipc-set-prop -i com.lab126.btfd BTflightMode 0
			lipc-set-prop -s com.lab126.btfd BTenable 1:2 && note "蓝牙已打开"
		fi ;;
	cmd:wifi_toggle)
		c=$(lipc-get-prop com.lab126.cmd wirelessEnable 2>/dev/null || echo 1)
		lipc-set-prop -i com.lab126.cmd wirelessEnable $((1 - c)) && {
			[ $c = 1 ] && note "无线已关闭" || note "无线已打开"
		} ;;
	esac
}

platform_battery() {
	echo "batt=$(lipc-get-prop com.lab126.powerd battLevel)"
	echo "charging=$(lipc-get-prop com.lab126.powerd isCharging)"
}
platform_status() {
	echo "bt=$(lipc-get-prop com.lab126.btfd BTstate)"
	echo "btdev=$(echo '{}' | lipc-hash-prop com.lab126.btfd ListConnected | awk -F'"' '/bd_name = / { printf "%s%s", n++ ? "、" : "", $2 }')"
	[ -n "$als" ] || { lipc-get-prop com.lab126.powerd alsLux >/dev/null 2>&1 && als=1 || als=0; }
	echo "auto=$([ $als = 1 ] && lipc-get-prop com.lab126.powerd flAuto)"
}
display_extra() { :; }

sleep_watch() {
	rm -f $W/power.fifo
	mkfifo $W/power.fifo
	lipc-wait-event -m com.lab126.powerd goingToScreenSaver,outOfScreenSaver,exitingScreenSaver > $W/power.fifo &
	echo $! > $W/lipc.pid
	F=/sys/class/graphics/fb0
	bpp=$(cat $F/bits_per_pixel 2>/dev/null)
	while read ev _; do
		case "$ev" in
		goingToScreenSaver)
			touch $X/ctl/sleep
			usleep 300000 2>/dev/null || sleep 1
			pan=$(cat $F/pan 2>/dev/null)
			screensaver_show
			t "screensaver on" ;;
		outOfScreenSaver)
			rm -f $X/ctl/sleep
			p=$(cat $F/pan 2>/dev/null)
			[ -n "$pan" ] && [ "$p" != "$pan" ] && echo "$pan" > $F/pan 2>/dev/null
			echo redraw > $X/epd.fifo
			[ "$bpp" = 32 ] && { sleep 2; [ -f $X/ctl/sleep ] || echo "rows 0 9999" > $X/epd.fifo; } &
			wifi_ps_off
			t "screensaver off" ;;
		exitingScreenSaver)
			[ "$bpp" = 32 ] && [ ! -f $X/ctl/sleep ] && echo redraw > $X/epd.fifo ;;
		esac
	done < $W/power.fifo
}

wifi_ps_off() {
	iwconfig wlan0 2>/dev/null | grep -q "Power Management:on" && iwconfig wlan0 power off && touch $W/wifi.ps
}

net_setup() {
	{ for d in $ANDROID_DNS; do echo "nameserver $d"; done
	  grep "^nameserver" "$(readlink -f /etc/resolv.conf)" 2>/dev/null
	} > $W/resolv.conf
	wifi_ps_off
}

net_start() {
	rm -f $W/slirp.sock
	unshare -m sh -c "{ mount --make-rprivate / 2>/dev/null || true; } && { mount --bind $W/resolv.conf /etc/resolv.conf; true; } &&
		exec $BIN/slirp4netns --mtu=1500 --cidr=$NET.0/24 --api-socket $W/slirp.sock $P eth0" > $W/slirp.log 2>&1 &
	echo $! > $W/slirp.pid
	i=0
	while [ $i -lt 10 ] && ! grep -q "sent tapfd" $W/slirp.log 2>/dev/null; do
		sleep 1
		i=$((i + 1))
	done
	lan_forward
}

lan_forward() {
	for port in $LAN_PORTS; do
		i=0
		r=
		while [ -z "$r" ] && [ $i -lt 10 ]; do
			r=$($BIN/slirpfwd $W/slirp.sock "{\"execute\":\"add_hostfwd\",\"arguments\":{\"proto\":\"tcp\",\"host_addr\":\"0.0.0.0\",\"host_port\":$port,\"guest_addr\":\"$NET.15\",\"guest_port\":$port}}" 2>&1)
			[ -n "$r" ] || usleep 200000
			i=$((i + 1))
		done
		case "$r" in
			*return*) iptables -I INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null && echo "$port" >> $W/lan.fw
				t "lan: $port" ;;
			*) t "lan: $port not forwarded: $r" ;;
		esac
	done
}

hostnet_args() { :; }

net_cleanup() {
	for p in $(cat $W/lan.fw 2>/dev/null); do
		iptables -D INPUT -p tcp --dport $p -j ACCEPT 2>/dev/null
	done
	rm -f $W/lan.fw
}

cns() { nsenter -t $P -m -p -r -w "$@"; }

container_child() { read -r P _ < /proc/$1/task/$1/children 2>/dev/null; }

touch_keys() {
	KFB_KEYS=$(awk '/^N: Name=/ { m = $0 ~ /"kindle-input-pt"/ }
		m && /^H: Handlers=/ { for (i = 1; i <= NF; i++) if (match($i, /event[0-9]+$/)) { print "/dev/input/" substr($i, RSTART); exit } }' /proc/bus/input/devices)
	[ -n "$KFB_KEYS" ] && chmod 666 $KFB_KEYS
	KFB_FTAP=$(awk '/^N: Name=/ { m = $0 ~ /"gesture_tap"/ }
		m && /^H: Handlers=/ { for (i = 1; i <= NF; i++) if (match($i, /event[0-9]+$/)) { print "/dev/input/" substr($i, RSTART); exit } }' /proc/bus/input/devices)
	[ -n "$KFB_FTAP" ] && chmod 666 $KFB_FTAP
	export KFB_KEYS KFB_FTAP
}
touch_extra() { echo "key 65   VOLUME_DOWN" > $W/kl/gesture_tap.kl; }

device_label() {
	case "$deviceName" in
		PaperWhite*) echo "Kindle Paperwhite ${deviceName#PaperWhite }" ;;
		"Basic 5") echo "Kindle 2024" ;;
		"Basic 4") echo "Kindle 2022" ;;
		[Cc]olor[Ss]oft*) echo "Kindle Colorsoft" ;;
		*) echo "Kindle $deviceName" ;;
	esac
}
firmware_version() { sed -n 's/^Kindle \([0-9.]*\).*/\1/p' /etc/prettyversion.txt 2>/dev/null; }

# 没有网络和 pid 命名空间的老内核。系统分区不写，镜像挂在用户分区上。
bourbon_run() {
	bourbon_android
}
