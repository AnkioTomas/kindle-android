# 兼容库是 surfaceflinger 里写帧缓冲的那块。
# 把编好的 libkindleshim.so 放在 bin/，启动时拷进 tmpfs，再绑进容器。
shim_open() {
	src=
	if [ -s $B/bin/libkindleshim.so ]; then
		src=$B/bin/libkindleshim.so
	elif [ -s $R/system/lib/libkindleshim.so ]; then
		src=$R/system/lib/libkindleshim.so
	fi
	if [ -z "$src" ]; then
		t "shim: libkindleshim.so missing"
		if [ -x $BIN/fbink ]; then
			$BIN/fbink -q -c -f " "
			$BIN/fbink -q -m -t regular=$KFONT,px=$((viewHeight / 22)),top=$((viewHeight * 22 / 100)) "kindle-android"
			$BIN/fbink -q -m -t regular=$KFONT,px=$((viewHeight / 40)),top=$((viewHeight * 40 / 100)) "缺少 libkindleshim.so"
		fi
		sleep 15
		return 1
	fi
	cp $src $W/libkindleshim.so || return 1
	chmod 644 $W/libkindleshim.so
	echo state=local > $W/license.info
	t "shim: $src"
}
