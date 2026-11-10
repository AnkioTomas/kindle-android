/* 在宿主上建一个虚拟键盘，把 /dev/kfb/keys 里的 back/home/menu/switch 送进去。
 * 容器的 /dev 是私有 tmpfs，里面 ioctl UI_DEV_CREATE 建出来的节点安卓看不到。
 * 启动器把这里打印的 event 节点绑进容器的 /dev/input/event3。
 */
#include <fcntl.h>
#include <linux/input.h>
#include <linux/uinput.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#ifndef KEY_APP_SWITCH
#define KEY_APP_SWITCH 580
#endif

static int emit(int fd, unsigned short type, unsigned short code, int value)
{
	struct input_event ev;

	memset(&ev, 0, sizeof ev);
	ev.type = type;
	ev.code = code;
	ev.value = value;
	return write(fd, &ev, sizeof ev) == (ssize_t)sizeof ev ? 0 : -1;
}

static void tap(int fd, int code)
{
	emit(fd, EV_KEY, code, 1);
	emit(fd, EV_SYN, SYN_REPORT, 0);
	emit(fd, EV_KEY, code, 0);
	emit(fd, EV_SYN, SYN_REPORT, 0);
}

static int code_of(const char *s)
{
	if (!strcmp(s, "back"))
		return KEY_BACK;
	if (!strcmp(s, "home"))
		return KEY_HOME;
	if (!strcmp(s, "menu"))
		return KEY_MENU;
	if (!strcmp(s, "switch"))
		return KEY_APP_SWITCH;
	return -1;
}

static int find_event(char *out, int cap)
{
	int i;

	for (i = 0; i < 32; i++) {
		char path[64], name[64];
		int fd, n;

		snprintf(path, sizeof path, "/sys/class/input/event%d/device/name", i);
		fd = open(path, O_RDONLY);
		if (fd < 0)
			continue;
		n = read(fd, name, sizeof name - 1);
		close(fd);
		if (n <= 0)
			continue;
		if (name[n - 1] == '\n')
			n--;
		name[n] = 0;
		if (strcmp(name, "kindle-keys"))
			continue;
		snprintf(out, cap, "/dev/input/event%d", i);
		return 0;
	}
	return -1;
}

int main(int argc, char **argv)
{
	int fd, fifo;
	struct uinput_user_dev dev;
	char path[64], line[32];
	int i, n;

	if (argc != 2)
		return 2;
	fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
	if (fd < 0)
		return 1;
	ioctl(fd, UI_SET_EVBIT, EV_KEY);
	ioctl(fd, UI_SET_KEYBIT, KEY_BACK);
	ioctl(fd, UI_SET_KEYBIT, KEY_HOME);
	ioctl(fd, UI_SET_KEYBIT, KEY_MENU);
	ioctl(fd, UI_SET_KEYBIT, KEY_APP_SWITCH);
	memset(&dev, 0, sizeof dev);
	snprintf(dev.name, UINPUT_MAX_NAME_SIZE, "kindle-keys");
	dev.id.bustype = BUS_VIRTUAL;
	if (write(fd, &dev, sizeof dev) != (ssize_t)sizeof dev)
		return 1;
	if (ioctl(fd, UI_DEV_CREATE) < 0)
		return 1;
	path[0] = 0;
	for (i = 0; i < 50 && find_event(path, sizeof path) < 0; i++)
		usleep(20000);
	if (!path[0])
		return 1;
	printf("%s\n", path);
	fflush(stdout);

	fifo = open(argv[1], O_RDWR);
	if (fifo < 0)
		return 1;
	n = 0;
	for (;;) {
		char b;
		int r = read(fifo, &b, 1);
		int c;
		if (r <= 0)
			break;
		if (b != '\n') {
			if (n < (int)sizeof line - 1)
				line[n++] = b;
			continue;
		}
		line[n] = 0;
		n = 0;
		c = code_of(line);
		if (c >= 0)
			tap(fd, c);
	}
	ioctl(fd, UI_DEV_DESTROY);
	return 0;
}
