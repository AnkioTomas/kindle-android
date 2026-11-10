/* 无框架时冒充 com.lab126.kaf 的 frameworkStarted。
 * 进程必须活着：powerd 问的是这个服务，不是一个已经退出的 set-prop。
 * liblipc 在 Kindle 上，dlopen，不在交叉编译机上链接。
 * 调用约定：
 *   LipcOpen("com.lab126.kaf")
 *   LipcRegisterIntProperty(handle, "frameworkStarted", getter, NULL, NULL)
 *   getter 把第三个参数指向的 int 写成 1，返回 0
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <unistd.h>

typedef void *lipc_t;
typedef lipc_t (*open_fn)(const char *);
typedef int (*reg_fn)(lipc_t, const char *, void *, void *, void *);
typedef void (*close_fn)(lipc_t);

static int framework_started(void *lipc, const char *name, int *value)
{
	(void)lipc;
	(void)name;
	*value = 1;
	return 0;
}

int main(void)
{
	void *so;
	open_fn open;
	reg_fn reg;
	close_fn close;
	int i;

	so = dlopen("liblipc.so", RTLD_NOW);
	if (!so)
		goto fail;
	open = (open_fn)dlsym(so, "LipcOpen");
	reg = (reg_fn)dlsym(so, "LipcRegisterIntProperty");
	close = (close_fn)dlsym(so, "LipcClose");
	if (!open || !reg || !close)
		goto fail;

	for (i = 0; i < 60; i++) {
		lipc_t h = open("com.lab126.kaf");
		if (h && reg(h, "frameworkStarted", framework_started, NULL, NULL) == 0) {
			for (;;)
				pause();
		}
		if (h)
			close(h);
		sleep(1);
	}
fail:
	fprintf(stderr, "kafstub: cannot register com.lab126.kaf frameworkStarted\n");
	return 1;
}
