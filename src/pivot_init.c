/* 两个入口，同一个静态二进制。
 *
 *   pivot_init --detach <cmd> [args...]
 *       新会话、uid 0、关掉多余 fd，再 exec。启动器用它脱离书库提权留下的身份。
 *       顺手把 root 的用户会话钥匙环链进当前会话，给 fscrypt 用。失败不致命。
 *
 *   pivot_init <newroot>
 *       切到已经准备好的安卓根，exec /init --second-stage。
 *       旧根挂在 newroot/dev/oldroot：/dev 是启动器刚挂的 tmpfs，根已经只读也能建。
 *
 * 这里不做 seccomp 过滤。
 */
#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <linux/keyctl.h>

static void join_keys(void)
{
	syscall(SYS_keyctl, KEYCTL_JOIN_SESSION_KEYRING, NULL);
	syscall(SYS_keyctl, KEYCTL_LINK,
		KEY_SPEC_USER_SESSION_KEYRING, KEY_SPEC_SESSION_KEYRING);
}

static int do_detach(char **argv)
{
	int fd;

	if (setsid() < 0 && errno != EPERM)
		perror("pivot_init: setsid");
	if (setresgid(0, 0, 0) < 0)
		perror("pivot_init: setresgid");
	if (setresuid(0, 0, 0) < 0)
		perror("pivot_init: setresuid");
	join_keys();
	for (fd = 3; fd < 256; fd++)
		close(fd);
	execvp(argv[0], argv);
	perror("pivot_init: exec");
	return 127;
}

static int do_pivot(const char *root)
{
	char *init_argv[] = { "/init", "--second-stage", NULL };

	if (chdir(root) < 0) {
		perror("pivot_init: chdir");
		return 1;
	}
	if (mkdir("dev/oldroot", 0755) < 0 && errno != EEXIST) {
		perror("pivot_init: mkdir old root");
		return 1;
	}
	if (syscall(SYS_pivot_root, ".", "dev/oldroot") < 0) {
		perror("pivot_init: pivot_root");
		return 1;
	}
	if (umount2("dev/oldroot", MNT_DETACH) < 0)
		perror("pivot_init: umount old root");
	rmdir("dev/oldroot");
	chdir("/");
	execve("/init", init_argv, environ);
	perror("pivot_init: execve /init");
	return 127;
}

int main(int argc, char **argv)
{
	if (argc >= 3 && strcmp(argv[1], "--detach") == 0)
		return do_detach(argv + 2);
	if (argc == 2)
		return do_pivot(argv[1]);
	fprintf(stderr, "usage: pivot_init <newroot>\n"
			"       pivot_init --detach <cmd> [args...]\n");
	return 2;
}
