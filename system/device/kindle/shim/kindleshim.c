/* 预加载进每个进程，只在 surfaceflinger 里干活。
 *
 * gralloc 写 /dev/graphics/fb0。宿主把它和 /dev/epd 都绑到 Kindle 的帧缓冲。
 * 这里比较可见页，再刷脏行。
 * 波形跟 /dev/kfb/epd.conf 一致：DU 1，GC16 2，REAGL 4，A2 6，AUTO 257。
 * PW5 走 MTK hwtcon。fb 名是 mxc_epdc_fb 时走 lab126 的 72 字节更新，
 * 主机上的 4 和 6 分别换成这颗控制器的 REAGL 8 和 A2 4。
 *
 * 这一版不改 gamma，也不发翻页滑动。epd.conf 里这两项读进来就丢掉。
 * 按键不走容器里的 /dev/uinput：容器的 /dev 是私有 tmpfs，建出来的 event 节点
 * 安卓看不见。按键名写到 /dev/kfb/keys，由宿主的 keyinject 注入。
 */
#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <linux/input.h>
#include <poll.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define KFB "/dev/kfb"
#define EPD "/dev/epd"
#define TEMP_USE_AMBIENT 0x1000
#define EPDC_FLAG_USE_DITHERING_Y1 0x2000

struct epd_rect {
	uint32_t top, left, width, height;
};
struct epd_alt {
	uint32_t phys_addr, width, height;
	struct epd_rect region;
};
struct epd_swipe {
	uint32_t direction, steps;
};
struct epd_update {
	struct epd_rect region;
	uint32_t waveform_mode;
	uint32_t update_mode;
	uint32_t update_marker;
	int temp;
	unsigned int flags;
	int dither_mode;
	int quant_bit;
	struct epd_alt alt;
	struct epd_swipe swipe;
	uint32_t hist_bw, hist_gray, ts_pxp, ts_epdc;
};
#define MXCFB_SEND_UPDATE_MTK _IOW('F', 0x2E, struct epd_update)

/* 这台 KT2 接受的请求是 0x4048462E，结构正好 72 字节。 */
struct epd_update_lab {
	struct epd_rect region;
	uint32_t waveform_mode;
	uint32_t update_mode;
	uint32_t update_marker;
	uint32_t hist_bw;
	uint32_t hist_gray;
	int temp;
	unsigned int flags;
	struct epd_alt alt;
};
#define MXCFB_SEND_UPDATE_LAB _IOW('F', 0x2E, struct epd_update_lab)
typedef char epd_update_lab_size[(sizeof(struct epd_update_lab) == 72) ? 1 : -1];

static int classic;
static int dither = 1;
static int local_wfm = 1;
static int turn_wfm = 4;
static int full_every;
static int page_count;
static uint32_t marker = 1;
static volatile int want_full;
static int screen_w = 1072;
static int screen_h = 1448;

/* gestures 文件：7 个动作，左/右半屏滑动模式，双指窗口毫秒，角落按住毫秒。 */
static int g_act[7];
static int g_vl, g_vr, g_window = 50, g_corner_ms = 2000;

static int is_surfaceflinger(void)
{
	char buf[64];
	int fd = open("/proc/self/cmdline", O_RDONLY);
	int n;

	if (fd < 0)
		return 0;
	n = read(fd, buf, sizeof buf - 1);
	close(fd);
	if (n <= 0)
		return 0;
	buf[n] = 0;
	return strcmp(buf, "surfaceflinger") == 0
		|| strcmp(buf, "/system/bin/surfaceflinger") == 0;
}

static void load_geom(void)
{
	FILE *f = fopen(KFB "/geom", "r");
	int w, h;

	if (f && fscanf(f, "%d %d", &w, &h) == 2 && w > 0 && h > 0) {
		screen_w = w;
		screen_h = h;
	}
	if (f)
		fclose(f);
}

static void load_conf(void)
{
	FILE *f = fopen(KFB "/epd.conf", "r");
	char line[4096];
	int d, local, every, turn;

	if (!f)
		return;
	if (fgets(line, sizeof line, f) &&
	    sscanf(line, "%d %*d %*d %d %*d", &d, &local) == 2) {
		dither = d;
		local_wfm = local;
	}
	fgets(line, sizeof line, f);
	if (fgets(line, sizeof line, f) && sscanf(line, "%d %d", &every, &turn) == 2) {
		full_every = every;
		turn_wfm = turn;
	}
	fclose(f);
}

static void load_gestures(void)
{
	FILE *f = fopen(KFB "/gestures", "r");
	int i;

	if (!f)
		return;
	for (i = 0; i < 7; i++)
		if (fscanf(f, "%d", &g_act[i]) != 1)
			g_act[i] = 0;
	if (fscanf(f, "%d %d %d %d", &g_vl, &g_vr, &g_window, &g_corner_ms) != 4) {
		g_vl = g_vr = 0;
		g_window = 50;
		g_corner_ms = 2000;
	}
	fclose(f);
}

static int panel_waveform(int waveform)
{
	if (!classic)
		return waveform;
	if (waveform == 4)
		return 8;
	if (waveform == 6)
		return 4;
	return waveform;
}

static void send_update(int fd, int y, int h, int waveform, int full)
{
	if (y < 0 || h <= 0)
		return;
	if (y + h > screen_h)
		h = screen_h - y;
	if (h <= 0)
		return;
	waveform = panel_waveform(waveform);
	if (classic) {
		struct epd_update_lab u;

		memset(&u, 0, sizeof u);
		u.region.top = y;
		u.region.width = screen_w;
		u.region.height = h;
		u.waveform_mode = waveform;
		u.update_mode = full ? 1 : 0;
		u.update_marker = marker++;
		u.temp = TEMP_USE_AMBIENT;
		ioctl(fd, MXCFB_SEND_UPDATE_LAB, &u);
		return;
	}
	{
		struct epd_update u;

		memset(&u, 0, sizeof u);
		u.region.top = y;
		u.region.width = screen_w;
		u.region.height = h;
		u.waveform_mode = waveform;
		u.update_mode = full ? 1 : 0;
		u.update_marker = marker++;
		u.temp = TEMP_USE_AMBIENT;
		if (dither)
			u.flags |= EPDC_FLAG_USE_DITHERING_Y1;
		ioctl(fd, MXCFB_SEND_UPDATE_MTK, &u);
	}
}

static void fifo_line(const char *path, const char *s)
{
	int fd = open(path, O_WRONLY | O_NONBLOCK);
	if (fd < 0)
		return;
	write(fd, s, strlen(s));
	close(fd);
}

static void touch_file(const char *path)
{
	int fd = open(path, O_CREAT | O_WRONLY, 0644);
	if (fd >= 0)
		close(fd);
}

static void put_app(const char *s)
{
	int fd = open(KFB "/ctl/app.tmp", O_CREAT | O_WRONLY | O_TRUNC, 0644);
	if (fd < 0)
		return;
	write(fd, s, strlen(s));
	close(fd);
	rename(KFB "/ctl/app.tmp", KFB "/ctl/app");
}

/* 动作编号跟宿主 GESTURE_ACTIONS 一致。 */
static void act(int id)
{
	if (access(KFB "/ctl/nogestures", F_OK) == 0)
		return;
	switch (id) {
	case 1:
		want_full = 1;
		break;
	case 2:
		if (access(KFB "/ctl/invert", F_OK) == 0)
			unlink(KFB "/ctl/invert");
		else
			touch_file(KFB "/ctl/invert");
		break;
	case 3:
		fifo_line(KFB "/keys", "back\n");
		break;
	case 4:
		fifo_line(KFB "/keys", "home\n");
		break;
	case 5:
		fifo_line(KFB "/keys", "switch\n");
		break;
	case 6:
		fifo_line(KFB "/keys", "menu\n");
		break;
	case 7:
		fifo_line(KFB "/kfb.fifo", "cmd:fl_toggle\n");
		break;
	case 8:
		fifo_line(KFB "/kfb.fifo", "cmd:wifi_toggle\n");
		break;
	case 9:
		fifo_line(KFB "/kfb.fifo", "cmd:suspend\n");
		break;
	case 10:
		touch_file(KFB "/ctl/exit");
		break;
	case 11:
		fifo_line(KFB "/kfb.fifo", "cmd:bt_toggle\n");
		break;
	case 12:
		put_app("home\n");
		break;
	default:
		break;
	}
}

static int read_cmd(int fd, char *buf, int cap)
{
	static char hold[128];
	static int n;
	char *nl;
	int r;

	for (;;) {
		nl = memchr(hold, '\n', n);
		if (nl || n >= (int)sizeof hold - 1)
			break;
		r = read(fd, hold + n, sizeof hold - 1 - n);
		if (r <= 0)
			break;
		n += r;
	}
	nl = memchr(hold, '\n', n);
	if (!nl) {
		if (n >= (int)sizeof hold - 1)
			n = 0;
		return 0;
	}
	if (nl - hold >= cap)
		nl = hold + cap - 1;
	memcpy(buf, hold, nl - hold);
	buf[nl - hold] = 0;
	n -= (nl + 1 - hold);
	memmove(hold, nl + 1, n);
	return 1;
}

static void *refresh(void *unused)
{
	int fd, fifo, y, stride, shown = 0;
	struct fb_fix_screeninfo fi;
	struct fb_var_screeninfo vi;
	size_t bytes, off;
	unsigned char *map, *cur, *prev;
	char line[64];

	(void)unused;
	fd = open(EPD, O_RDWR);
	if (fd < 0)
		return NULL;
	if (ioctl(fd, FBIOGET_FSCREENINFO, &fi) < 0 || ioctl(fd, FBIOGET_VSCREENINFO, &vi) < 0)
		return NULL;
	classic = strncmp(fi.id, "mxc_epdc_fb", 11) == 0;
	map = mmap(NULL, fi.smem_len, PROT_READ, MAP_SHARED, fd, 0);
	if (map == MAP_FAILED)
		return NULL;
	load_geom();
	load_conf();
	stride = fi.line_length;
	if (stride <= 0 || vi.yres <= 0)
		return NULL;
	screen_w = vi.xres;
	screen_h = vi.yres;
	bytes = (size_t)stride * vi.yres;
	prev = calloc(1, bytes);
	if (!prev)
		return NULL;
	fifo = open(KFB "/epd.fifo", O_RDONLY | O_NONBLOCK);

	for (;;) {
		int y0 = -1, y1 = -1, full = 0, waveform = local_wfm;

		if (access(KFB "/ctl/sleep", F_OK) == 0) {
			usleep(100000);
			continue;
		}
		if (fifo >= 0) {
			while (read_cmd(fifo, line, sizeof line)) {
				int a, b;
				if (!strncmp(line, "reload", 6))
					load_conf();
				else if (!strncmp(line, "redraw", 6))
					full = 1;
				else if (sscanf(line, "rows %d %d", &a, &b) == 2) {
					if (a < 0)
						a = 0;
					if (b >= screen_h)
						b = screen_h - 1;
					if (y0 < 0 || a < y0)
						y0 = a;
					if (b > y1)
						y1 = b;
				}
			}
		}
		if (want_full) {
			want_full = 0;
			full = 1;
		}
		if (ioctl(fd, FBIOGET_VSCREENINFO, &vi) < 0) {
			usleep(50000);
			continue;
		}
		off = (size_t)vi.yoffset * stride;
		if (off + bytes > fi.smem_len) {
			usleep(50000);
			continue;
		}
		cur = map + off;
		if (!full && y0 < 0) {
			for (y = 0; y < screen_h; y++) {
				if (memcmp(cur + (size_t)y * stride, prev + (size_t)y * stride, stride)) {
					if (y0 < 0)
						y0 = y;
					y1 = y;
				}
			}
		}
		if (full || y0 >= 0) {
			int h, span;
			if (y0 < 0) {
				y0 = 0;
				y1 = screen_h - 1;
			}
			h = y1 - y0 + 1;
			span = h * 2 > screen_h;
			if (full || span) {
				waveform = turn_wfm;
				if (span && full_every && ++page_count >= full_every) {
					full = 1;
					page_count = 0;
				}
			}
			send_update(fd, y0, h, waveform, full);
			memcpy(prev, cur, bytes);
			if (!shown) {
				touch_file(KFB "/ctl/shown");
				shown = 1;
			}
		}
		usleep(50000);
	}
}

static long since_ms(struct timespec t0)
{
	struct timespec now;
	clock_gettime(CLOCK_MONOTONIC, &now);
	return (now.tv_sec - t0.tv_sec) * 1000L + (now.tv_nsec - t0.tv_nsec) / 1000000L;
}

static int corner_of(int x, int y)
{
	int band = (screen_w < screen_h ? screen_w : screen_h) / 8;
	int left = x < band;
	int right = x >= screen_w - band;
	int top = y < band;
	int bottom = y >= screen_h - band;

	if (left && top)
		return 3;
	if (right && top)
		return 4;
	if (left && bottom)
		return 5;
	if (right && bottom)
		return 6;
	return -1;
}

static void vertical_swipe(int x, int dy)
{
	int mode = x < screen_w / 2 ? g_vl : g_vr;
	char buf[32];
	int step = dy < 0 ? 1 : -1;

	if (mode == 1)
		snprintf(buf, sizeof buf, "cmd:fl_step=%+d\n", step);
	else if (mode == 2)
		snprintf(buf, sizeof buf, "cmd:warmth_step=%+d\n", step);
	else
		return;
	fifo_line(KFB "/kfb.fifo", buf);
}

struct finger {
	int down, have, x, y, sx, sy;
	struct timespec t0;
};

static void *gestures(void *unused)
{
	int fd = open("/dev/input/event0", O_RDONLY | O_NONBLOCK);
	struct pollfd pfd;
	struct input_event ev;
	struct finger f[2];
	struct timespec two_t;
	int slot = 0, two = 0, held_fired = 0;
	int two_x[2], two_y[2];
	struct stat st;
	time_t g_mtime = 0;
	int prev = 0;

	(void)unused;
	if (fd < 0)
		return NULL;
	memset(f, 0, sizeof f);
	load_geom();
	load_gestures();
	if (stat(KFB "/gestures", &st) == 0)
		g_mtime = st.st_mtime;
	pfd.fd = fd;
	pfd.events = POLLIN;

	for (;;) {
		int wait = 200;
		int n, cnt, slop;

		if (f[0].down + f[1].down == 1 && !held_fired && !two) {
			int i = f[0].down ? 0 : 1;
			long left = g_corner_ms - since_ms(f[i].t0);
			if (left < wait)
				wait = left < 1 ? 1 : (int)left;
		}
		n = poll(&pfd, 1, wait);
		if (stat(KFB "/gestures", &st) == 0 && st.st_mtime != g_mtime) {
			g_mtime = st.st_mtime;
			load_gestures();
		}
		cnt = f[0].down + f[1].down;
		if (n == 0 && cnt == 1 && !held_fired && !two) {
			int i = f[0].down ? 0 : 1;
			int c;
			if (since_ms(f[i].t0) < g_corner_ms)
				continue;
			c = corner_of(f[i].x, f[i].y);
			act(c >= 0 ? g_act[c] : g_act[1]);
			held_fired = 1;
			continue;
		}
		if (n <= 0)
			continue;
		if (read(fd, &ev, sizeof ev) != (ssize_t)sizeof ev)
			continue;
		if (ev.type == EV_ABS && ev.code == ABS_MT_SLOT && ev.value >= 0 && ev.value < 2)
			slot = ev.value;
		else if (ev.type == EV_ABS && ev.code == ABS_MT_TRACKING_ID && slot < 2) {
			if (ev.value >= 0) {
				f[slot].down = 1;
				f[slot].have = 0;
				clock_gettime(CLOCK_MONOTONIC, &f[slot].t0);
			} else {
				f[slot].down = 0;
			}
		} else if (ev.type == EV_ABS && ev.code == ABS_MT_POSITION_X && slot < 2) {
			f[slot].x = ev.value;
			if (!f[slot].have)
				f[slot].sx = ev.value;
		} else if (ev.type == EV_ABS && ev.code == ABS_MT_POSITION_Y && slot < 2) {
			f[slot].y = ev.value;
			if (!f[slot].have)
				f[slot].sy = ev.value;
		} else if (ev.type == EV_SYN && ev.code == SYN_REPORT) {
			int i;
			for (i = 0; i < 2; i++)
				if (f[i].down)
					f[i].have = 1;
			cnt = f[0].down + f[1].down;
			slop = (screen_w < screen_h ? screen_w : screen_h) / 12;
			if (slop < 40)
				slop = 40;
			if (cnt == 2 && !two) {
				two = 1;
				two_x[0] = f[0].x;
				two_y[0] = f[0].y;
				two_x[1] = f[1].x;
				two_y[1] = f[1].y;
				clock_gettime(CLOCK_MONOTONIC, &two_t);
			}
			if (prev > 0 && cnt == 0) {
				if (two) {
					int moved = 0;
					for (i = 0; i < 2; i++) {
						int dx = f[i].x - two_x[i];
						int dy = f[i].y - two_y[i];
						if (dx < 0)
							dx = -dx;
						if (dy < 0)
							dy = -dy;
						if (dx > slop || dy > slop)
							moved = 1;
					}
					if (!moved && since_ms(two_t) <= g_window)
						act(g_act[0]);
				} else if (!held_fired) {
					for (i = 0; i < 2; i++)
						if (f[i].have)
							break;
					if (i < 2) {
						int dx = f[i].x - f[i].sx;
						int dy = f[i].y - f[i].sy;
						int adx = dx < 0 ? -dx : dx;
						int ady = dy < 0 ? -dy : dy;
						if (adx > slop && adx > ady)
							act(g_act[2]);
						else if (ady > slop)
							vertical_swipe(f[i].x, dy);
					}
				}
				two = 0;
				held_fired = 0;
				f[0].have = f[1].have = 0;
			}
			prev = cnt;
		}
	}
}

__attribute__((constructor)) static void start(void)
{
	pthread_t a, b;

	if (!is_surfaceflinger())
		return;
	pthread_create(&a, NULL, refresh, NULL);
	pthread_create(&b, NULL, gestures, NULL);
	pthread_detach(a);
	pthread_detach(b);
}
