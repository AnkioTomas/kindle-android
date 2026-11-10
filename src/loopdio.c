/* 把 loop 设备的 direct-io 打开或还原。用法：loopdio /dev/loop/0 1 */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <linux/loop.h>
#include <sys/ioctl.h>

int main(int argc, char **argv)
{
	int fd, on;

	if (argc != 3) {
		fprintf(stderr, "usage: loopdio <loop-device> <0|1>\n");
		return 2;
	}
	fd = open(argv[1], O_RDWR);
	if (fd < 0) {
		perror(argv[1]);
		return 1;
	}
	on = atoi(argv[2]);
	if (ioctl(fd, LOOP_SET_DIRECT_IO, on) < 0) {
		perror("LOOP_SET_DIRECT_IO");
		return 1;
	}
	return 0;
}
