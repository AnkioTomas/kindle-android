# 书库入口经越狱 su 拉起，真实用户仍是 framework。框架一停，有权把这些进程收掉。
# 容器 init 是命名空间里的 1 号，外面的信号进不去，所以只剩它。先换成干净的 root 再继续。
detach_self() {
	cd /
	echo 0 > /proc/$$/oom_score_adj
	if [ -z "$ANDROID_DETACHED" ]; then
		exec env -i ANDROID_DETACHED=1 PATH="$PATH" \
			$BIN/pivot_init --detach sh "$0" "$@" </dev/null
	fi
	echo "== $(date) start"
	for s in HUP INT TERM; do trap "t 'got SIG$s'; exit 1" $s; done
}
