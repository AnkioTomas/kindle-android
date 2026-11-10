/* init 没跑。zygote 和 installd 都要现成的监听 fd，
 * 环境变量 ANDROID_SOCKET_<name> 指着它。system_server 会 ping installd，
 * 没有这个套接字就起不来 ActivityManager。
 */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

static int reserve_socket(const char *name)
{
	struct sockaddr_un addr;
	int fd;
	char path[64];

	snprintf(path, sizeof path, "/dev/socket/%s", name);
	unlink(path);
	fd = socket(AF_UNIX, SOCK_STREAM, 0);
	if (fd < 0)
		return -1;
	memset(&addr, 0, sizeof addr);
	addr.sun_family = AF_UNIX;
	snprintf(addr.sun_path, sizeof addr.sun_path, "%s", path);
	if (bind(fd, (struct sockaddr *)&addr, sizeof addr) < 0)
		return -1;
	chmod(path, 0666);
	return fd;
}

static void log_pipe(const char *name)
{
	char path[64], outp[64], buf[1024];
	int rd, n;

	snprintf(path, sizeof path, "/dev/log/%s", name);
	snprintf(outp, sizeof outp, "/data/log.%s", name);
	unlink(path);
	if (mkfifo(path, 0666) < 0)
		return;
	chmod(path, 0666);
	rd = open(path, O_RDWR);
	if (rd < 0)
		return;
	if (fork() == 0) {
		int out = open(outp, O_WRONLY | O_CREAT | O_TRUNC, 0644);
		while ((n = read(rd, buf, sizeof buf)) > 0) {
			if (out >= 0)
				write(out, buf, n);
		}
		_exit(0);
	}
	close(rd);
}

static void log_to(const char *path)
{
	int in = open("/dev/null", O_RDONLY);
	int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);

	if (in >= 0) {
		dup2(in, 0);
		if (in > 2)
			close(in);
	}
	if (fd < 0)
		return;
	dup2(fd, 1);
	dup2(fd, 2);
	if (fd > 2)
		close(fd);
}

static void property_service(int fd)
{
	char buf[128];
	int c, got, n;

	for (;;) {
		c = accept(fd, 0, 0);
		if (c < 0)
			continue;
		got = 0;
		while (got < 128) {
			n = read(c, buf + got, 128 - got);
			if (n <= 0)
				break;
			got += n;
		}
		close(c);
	}
}

static int property_listen(void)
{
	struct sockaddr_un addr;
	int fd;

	unlink("/dev/socket/property_service");
	fd = socket(AF_UNIX, SOCK_STREAM, 0);
	if (fd < 0)
		return -1;
	memset(&addr, 0, sizeof addr);
	addr.sun_family = AF_UNIX;
	snprintf(addr.sun_path, sizeof addr.sun_path, "/dev/socket/property_service");
	if (bind(fd, (struct sockaddr *)&addr, sizeof addr) < 0)
		return -1;
	chmod("/dev/socket/property_service", 0666);
	if (listen(fd, 8) < 0)
		return -1;
	return fd;
}

static void android_env(void)
{
	setenv("PATH", "/sbin:/system/sbin:/system/bin:/system/xbin", 1);
	setenv("LD_LIBRARY_PATH", "/vendor/lib:/system/lib", 1);
	setenv("ANDROID_ROOT", "/system", 1);
	setenv("ANDROID_ASSETS", "/system/app", 1);
	setenv("ANDROID_DATA", "/data", 1);
	setenv("ANDROID_STORAGE", "/storage", 1);
	setenv("EXTERNAL_STORAGE", "/storage/sdcard0", 1);
	setenv("ASEC_MOUNTPOINT", "/mnt/asec", 1);
	setenv("LOOP_MOUNTPOINT", "/mnt/obb", 1);
	setenv("BOOTCLASSPATH",
		"/system/framework/core.jar:"
		"/system/framework/conscrypt.jar:"
		"/system/framework/okhttp.jar:"
		"/system/framework/core-junit.jar:"
		"/system/framework/bouncycastle.jar:"
		"/system/framework/ext.jar:"
		"/system/framework/framework.jar:"
		"/system/framework/framework2.jar:"
		"/system/framework/telephony-common.jar:"
		"/system/framework/voip-common.jar:"
		"/system/framework/mms-common.jar:"
		"/system/framework/android.policy.jar:"
		"/system/framework/services.jar:"
		"/system/framework/apache-xml.jar:"
		"/system/framework/webviewchromium.jar", 1);
}

int main(void)
{
	int zfd, ifd, pfd;
	char zenv[16], ienv[16];
	pid_t pid;

	mkdir("/dev/socket", 0755);
	mkdir("/data/local", 0755);
	mkdir("/data/local/tmp", 0755);
	mkdir("/data/dalvik-cache", 0771);
	mkdir("/data/resource-cache", 0771);
	mkdir("/data/data", 0771);
	mkdir("/data/app", 0771);
	mkdir("/data/app-private", 0771);
	mkdir("/data/app-lib", 0771);
	mkdir("/data/security", 0711);
	chown("/data/dalvik-cache", 1000, 1000);
	chown("/data/resource-cache", 1000, 1000);
	chown("/data/data", 1000, 1000);
	chown("/data/app", 1000, 1000);
	chown("/data/app-private", 1000, 1000);
	chown("/data/app-lib", 1000, 1000);
	chown("/data/security", 1000, 1000);
	mkdir("/data/system", 0775);
	mkdir("/data/user", 0771);
	mkdir("/data/app", 0771);
	mkdir("/data/property", 0700);
	mkdir("/data/anr", 0775);
	mkdir("/data/media", 0770);
	mkdir("/data/misc", 01771);
	mkdir("/storage", 0755);
	mkdir("/storage/sdcard0", 0755);
	mkdir("/mnt/asec", 0755);
	mkdir("/mnt/obb", 0755);
	mkdir("/data/system/ifw", 0771);
	mkdir("/data/system/users", 0771);
	mkdir("/data/system/users/0", 0771);
	mkdir("/data/system/usagestats", 0771);
	mkdir("/data/system/dropbox", 0771);
	chown("/data/system", 1000, 1000);
	chown("/data/system/ifw", 1000, 1000);
	chown("/data/system/users", 1000, 1000);
	chown("/data/system/users/0", 1000, 1000);
	chown("/data/system/usagestats", 1000, 1000);
	chown("/data/system/dropbox", 1000, 1000);
	chmod("/data/system", 0771);
	chmod("/data/anr", 0775);
	chown("/data/anr", 1000, 1000);
	mkdir("/dev/kfb", 0777);
	mkdir("/dev/kfb/ctl", 0777);
	mkdir("/dev/log", 0755);
	log_pipe("main");
	log_pipe("radio");
	log_pipe("events");
	log_pipe("system");
	android_env();
	pfd = property_listen();
	if (pfd >= 0 && fork() == 0)
		property_service(pfd);
	if (pfd >= 0)
		close(pfd);

	zfd = reserve_socket("zygote");
	ifd = reserve_socket("installd");
	if (zfd < 0 || ifd < 0) {
		perror("socket");
		return 1;
	}
	snprintf(zenv, sizeof zenv, "%d", zfd);
	snprintf(ienv, sizeof ienv, "%d", ifd);

	pid = fork();
	if (pid == 0) {
		setenv("ANDROID_SOCKET_installd", ienv, 1);
		log_to("/data/installd.log");
		execl("/system/bin/installd", "installd", (char *)0);
		_exit(127);
	}
	sleep(1);

	pid = fork();
	if (pid == 0) {
		setenv("ANDROID_SOCKET_zygote", zenv, 1);
		log_to("/data/zygote.log");
		execl("/system/bin/app_process", "app_process",
			"-Xzygote", "/system/bin",
			"--zygote", "--start-system-server", (char *)0);
		_exit(127);
	}
	return 0;
}
