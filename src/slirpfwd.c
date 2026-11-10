/* 往 slirp4netns 的 API 套接字发一条 JSON，读完回复打到 stdout。
 * 服务端读到写端关闭才解析，所以发完必须 shutdown(SHUT_WR)。
 * 用法：slirpfwd <socket> '<json>'
 */
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	int fd, n;
	struct sockaddr_un addr;
	char buf[4096];

	if (argc != 3) {
		fprintf(stderr, "usage: slirpfwd <socket> <json>\n");
		return 2;
	}
	fd = socket(AF_UNIX, SOCK_STREAM, 0);
	if (fd < 0) {
		perror("socket");
		return 1;
	}
	memset(&addr, 0, sizeof addr);
	addr.sun_family = AF_UNIX;
	if (strlen(argv[1]) >= sizeof addr.sun_path) {
		fprintf(stderr, "socket path too long\n");
		return 1;
	}
	memcpy(addr.sun_path, argv[1], strlen(argv[1]) + 1);
	if (connect(fd, (struct sockaddr *)&addr, sizeof addr) < 0) {
		perror("connect");
		return 1;
	}
	n = strlen(argv[2]);
	if (write(fd, argv[2], n) != n || write(fd, "\n", 1) != 1) {
		perror("write");
		return 1;
	}
	if (shutdown(fd, SHUT_WR) < 0) {
		perror("shutdown");
		return 1;
	}
	while ((n = read(fd, buf, sizeof buf)) > 0)
		fwrite(buf, 1, n, stdout);
	if (n < 0) {
		perror("read");
		return 1;
	}
	return 0;
}
