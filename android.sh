#!/bin/sh
# 在已越狱的 Kindle 上用命名空间跑 Android。书库入口或：sh android.sh [包名|home]
{
umask 022
D=$(cd "$(dirname "$0")" && pwd)
PLATFORM=kindle
U=/mnt/base-us
[ -d /mnt/onboard/.kobo ] && PLATFORM=kobo && U=/mnt/onboard
B=$U/${D##*/}
D=$B
S=$U/system/${B##*/}
W=/var/tmp/android
R=$S/rootfs
X=$W/kfb
LOG=$S/android.log
mkdir -p $S $W
chmod 755 $B/bin/* 2>/dev/null
t() { echo "[$(date +%H:%M:%S) up=$(cut -d' ' -f1 /proc/uptime)] $*"; }
A="sh $D/ashell.sh"
[ -f $D/platform/$PLATFORM.sh ] || { echo "no platform $PLATFORM"; exit 1; }
for m in $D/lib/*.sh $D/platform/$PLATFORM.sh; do . $m; done
BIN=$B/bin
USERSTORE=
platform_init
if [ "$1" != --in-ns ]; then
	if [ -z "$ANDROID_DETACHED" ] && ! mkdir $W/start.lock 2>/dev/null; then
		p=$(cat $W/start.lock/pid 2>/dev/null)
		[ -n "$p" ] && kill -0 $p 2>/dev/null && exit 0
	fi
	mkdir -p $W/start.lock
	echo $$ > $W/start.lock/pid
	trap 'rm -rf $W/start.lock' EXIT
fi
if [ -n "$BOURBON" ]; then
	bourbon_run
	exit
fi
userstore_setup || { command -v fatloop_restore >/dev/null && fatloop_restore; exit 1; }
settings_load
case $1 in
	--in-ns | "") ;;
	*) ANDROID_APP=$1 ;;
esac
[ "$1" = "--in-ns" ] && run_in_ns "$2" "$3" "$4"

[ "$(stat -c %s $LOG 2>/dev/null || echo 0)" -gt 1048576 ] && tail -c 262144 $LOG > $LOG.tmp && mv -f $LOG.tmp $LOG
exec >>$LOG 2>&1
detach_self "$@"
t "app: $ANDROID_APP"
P=$(cat $W/pid 2>/dev/null)
if [ -n "$P" ] && kill -0 $P 2>/dev/null; then
	app_open
	exit
fi
cleanup_stale
framework_stop
detect_screen && prepare_files && shim_open && mount_images || { sh $D/stop.sh >/dev/null 2>&1; exit 1; }
touch_setup
display_start
ls $B/apps/*.apk >/dev/null 2>&1 || { echo "$ANDROID_APP" > $X/ctl/app; HOME_OPENS=1; }
net_setup
zram_on
lowmem_drop_caches
container_start || { sh $D/stop.sh >/dev/null 2>&1; exit 1; }
net_start
after_boot &
watchdog &
echo $! > $W/watchdog.pid
sleep_watch &
echo $! > $W/sleep.pid
[ -f $W/pid ] && filebrowser_apply
}
