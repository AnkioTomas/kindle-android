/* 写出 bionic 4.4 的 /dev/__properties__。
 * init 没跑，属性区只有一个空根。property_get 全部落到默认值，
 * ro.kernel.qemu 读成 0，libEGL 就不会加载 libGLES_android.so。
 * 布局跟 bionic/libc/bionic/system_properties.c 的 prop_area 一致。
 */
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PROP_NAME_MAX 32
#define PROP_VALUE_MAX 92
#define PA_SIZE (128 * 1024)
#define PROP_AREA_MAGIC 0x504f5250u
#define PROP_AREA_VERSION 0xfc6ed0abu

struct prop_area {
	uint32_t bytes_used;
	uint32_t serial;
	uint32_t magic;
	uint32_t version;
	uint32_t reserved[28];
	char data[PA_SIZE - 128];
};

struct prop_bt {
	uint8_t namelen;
	uint8_t reserved[3];
	uint32_t prop;
	uint32_t left;
	uint32_t right;
	uint32_t children;
	char name[];
};

struct prop_info {
	uint32_t serial;
	char value[PROP_VALUE_MAX];
	char name[];
};

_Static_assert(sizeof(struct prop_bt) == 20, "prop_bt");
_Static_assert(sizeof(struct prop_info) == 96, "prop_info");
_Static_assert(__builtin_offsetof(struct prop_area, data) == 128, "data");

static struct prop_area area;
static const size_t data_size = sizeof(area.data);

static void *to_obj(uint32_t off)
{
	if (off > data_size)
		return NULL;
	return area.data + off;
}

static void *new_obj(size_t size, uint32_t *off)
{
	size = (size + 3u) & ~3u;
	if (area.bytes_used + size > data_size)
		return NULL;
	*off = area.bytes_used;
	void *p = area.data + area.bytes_used;
	area.bytes_used += size;
	return p;
}

static struct prop_bt *new_bt(const char *name, uint8_t namelen, uint32_t *off)
{
	uint32_t tmp;
	struct prop_bt *bt = new_obj(sizeof(*bt) + namelen + 1, &tmp);
	if (!bt)
		return NULL;
	memcpy(bt->name, name, namelen);
	bt->name[namelen] = 0;
	bt->namelen = namelen;
	*off = tmp;
	return bt;
}

static struct prop_info *new_info(const char *name, uint8_t namelen,
		const char *value, uint8_t valuelen, uint32_t *off)
{
	uint32_t tmp;
	struct prop_info *info = new_obj(sizeof(*info) + namelen + 1, &tmp);
	if (!info)
		return NULL;
	memcpy(info->name, name, namelen);
	info->name[namelen] = 0;
	info->serial = (uint32_t)valuelen << 24;
	memcpy(info->value, value, valuelen);
	info->value[valuelen] = 0;
	*off = tmp;
	return info;
}

static int cmp_name(const char *a, uint8_t alen, const char *b, uint8_t blen)
{
	if (alen < blen)
		return -1;
	if (alen > blen)
		return 1;
	return strncmp(a, b, alen);
}

static struct prop_bt *find_bt(struct prop_bt *bt, const char *name,
		uint8_t namelen, int alloc)
{
	while (bt) {
		int ret = cmp_name(name, namelen, bt->name, bt->namelen);
		if (ret == 0)
			return bt;
		if (ret < 0) {
			if (bt->left)
				bt = to_obj(bt->left);
			else if (!alloc)
				return NULL;
			else
				bt = new_bt(name, namelen, &bt->left);
		} else if (bt->right) {
			bt = to_obj(bt->right);
		} else if (!alloc) {
			return NULL;
		} else {
			bt = new_bt(name, namelen, &bt->right);
		}
	}
	return NULL;
}

static struct prop_info *find_prop(struct prop_bt *trie, const char *name,
		uint8_t namelen, const char *value, uint8_t valuelen, int alloc)
{
	const char *rest = name;

	while (1) {
		const char *sep = strchr(rest, '.');
		int want = sep != NULL;
		uint8_t nlen = want ? (uint8_t)(sep - rest) : (uint8_t)strlen(rest);
		struct prop_bt *root;

		if (!nlen)
			return NULL;
		if (trie->children)
			root = to_obj(trie->children);
		else if (alloc)
			root = new_bt(rest, nlen, &trie->children);
		else
			return NULL;
		if (!root)
			return NULL;
		trie = find_bt(root, rest, nlen, alloc);
		if (!trie)
			return NULL;
		if (!want)
			break;
		rest = sep + 1;
	}
	if (trie->prop)
		return to_obj(trie->prop);
	if (!alloc)
		return NULL;
	return new_info(name, namelen, value, valuelen, &trie->prop);
}

static int add_prop(const char *name, const char *value)
{
	size_t nlen = strlen(name);
	size_t vlen = strlen(value);
	struct prop_info *pi;

	if (nlen == 0 || nlen >= PROP_NAME_MAX || vlen >= PROP_VALUE_MAX)
		return -1;
	pi = find_prop((struct prop_bt *)area.data, name, (uint8_t)nlen,
			value, (uint8_t)vlen, 1);
	if (!pi)
		return -1;
	area.serial++;
	return 0;
}

static int get_prop(const char *name, char *value)
{
	struct prop_info *pi = find_prop((struct prop_bt *)area.data, name,
			(uint8_t)strlen(name), NULL, 0, 0);
	if (!pi) {
		value[0] = 0;
		return 0;
	}
	memcpy(value, pi->value, (pi->serial >> 24) + 1);
	return (int)(pi->serial >> 24);
}

static void walk(struct prop_bt *bt)
{
	struct prop_info *pi;

	if (!bt)
		return;
	if (bt->prop) {
		pi = to_obj(bt->prop);
		printf("%s=%s\n", pi->name, pi->value);
	}
	if (bt->left)
		walk(to_obj(bt->left));
	if (bt->right)
		walk(to_obj(bt->right));
	if (bt->children)
		walk(to_obj(bt->children));
}

static void load_file(const char *path)
{
	FILE *f = fopen(path, "r");
	char line[512];

	if (!f) {
		fprintf(stderr, "open %s: %s\n", path, strerror(errno));
		return;
	}
	while (fgets(line, sizeof line, f)) {
		char *eq;
		size_t n;

		if (line[0] == '#' || line[0] == '\n' || line[0] == '\r')
			continue;
		n = strlen(line);
		while (n && (line[n - 1] == '\n' || line[n - 1] == '\r'))
			line[--n] = 0;
		eq = strchr(line, '=');
		if (!eq || eq == line)
			continue;
		*eq = 0;
		if (add_prop(line, eq + 1) < 0)
			fprintf(stderr, "skip %s\n", line);
	}
	fclose(f);
}

static void init_area(void)
{
	memset(&area, 0, sizeof area);
	area.magic = PROP_AREA_MAGIC;
	area.version = PROP_AREA_VERSION;
	area.bytes_used = sizeof(struct prop_bt);
}

static int write_area(const char *path)
{
	FILE *f = fopen(path, "w");
	size_t n;

	if (!f) {
		fprintf(stderr, "write %s: %s\n", path, strerror(errno));
		return -1;
	}
	n = fwrite(&area, 1, PA_SIZE, f);
	if (fclose(f) != 0 || n != PA_SIZE) {
		fprintf(stderr, "short write %s\n", path);
		return -1;
	}
	return 0;
}

static int load_area(const char *path)
{
	FILE *f = fopen(path, "r");
	size_t n;

	if (!f)
		return -1;
	n = fread(&area, 1, PA_SIZE, f);
	fclose(f);
	if (n != PA_SIZE || area.magic != PROP_AREA_MAGIC)
		return -1;
	return 0;
}

int main(int argc, char **argv)
{
	char value[PROP_VALUE_MAX];
	static const char *forced[] = {
		"ro.kernel.qemu", "1",
		"ro.kernel.qemu.gles", "0",
		"debug.sf.nobootanimation", "1",
		"ro.sf.lcd_density", "167",
		"ro.zygote.disable_gl_preload", "1",
		"config.disable_network", "1",
		"config.disable_bluetooth", "1",
		"config.disable_telephony", "1",
		"config.disable_location", "1",
		"config.disable_noncore", "1",
		"config.disable_storage", "1",
		"config.disable_media", "1",
		"config.disable_renderscript", "true",
		"persist.sys.dalvik.vm.lib", "libdvm.so",
		NULL
	};
	int i;

	if (argc == 3 && strcmp(argv[1], "-g") == 0) {
		if (load_area(argv[2]) < 0)
			return 1;
		walk((struct prop_bt *)area.data);
		return 0;
	}
	if (argc == 4 && strcmp(argv[1], "-q") == 0) {
		if (load_area(argv[2]) < 0)
			return 1;
		get_prop(argv[3], value);
		printf("%s\n", value);
		return value[0] ? 0 : 1;
	}
	if (argc != 3) {
		fprintf(stderr, "usage: propseed build.prop /dev/__properties__\n");
		return 2;
	}

	init_area();
	for (i = 0; forced[i]; i += 2) {
		if (add_prop(forced[i], forced[i + 1]) < 0)
			return 1;
	}
	load_file(argv[1]);
	if (get_prop("ro.kernel.qemu", value) != 1 || strcmp(value, "1") != 0)
		return 1;
	if (get_prop("ro.kernel.qemu.gles", value) != 1 || strcmp(value, "0") != 0)
		return 1;
	if (get_prop("debug.sf.nobootanimation", value) != 1 || strcmp(value, "1") != 0)
		return 1;
	return write_area(argv[2]) == 0 ? 0 : 1;
}
