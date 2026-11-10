#include <linux/module.h>
#include <linux/kallsyms.h>
#include <linux/mm.h>
#include <linux/fs.h>
#include <linux/fdtable.h>
#include <linux/sched.h>
#include <linux/vmalloc.h>

/* 3.0.35-lab126 没把这些导出。kallsyms_lookup_name 是导出的。 */

static unsigned long (*zap_page_range_fn)(struct vm_area_struct *, unsigned long,
		unsigned long, struct zap_details *);
static void (*unmap_kernel_range_fn)(unsigned long, unsigned long);
static struct vm_struct *(*get_vm_area_fn)(unsigned long, unsigned long);
static int (*expand_files_fn)(struct files_struct *, int);
static struct files_struct *(*get_files_struct_fn)(struct task_struct *);
static void (*put_files_struct_fn)(struct files_struct *);
static int (*can_nice_fn)(const struct task_struct *, const int);
static struct sighand_struct *(*lock_sighand_fn)(struct task_struct *, unsigned long *);

int ksyms_bind(void)
{
	zap_page_range_fn = (void *)kallsyms_lookup_name("zap_page_range");
	unmap_kernel_range_fn = (void *)kallsyms_lookup_name("unmap_kernel_range");
	get_vm_area_fn = (void *)kallsyms_lookup_name("get_vm_area");
	expand_files_fn = (void *)kallsyms_lookup_name("expand_files");
	get_files_struct_fn = (void *)kallsyms_lookup_name("get_files_struct");
	put_files_struct_fn = (void *)kallsyms_lookup_name("put_files_struct");
	can_nice_fn = (void *)kallsyms_lookup_name("can_nice");
	lock_sighand_fn = (void *)kallsyms_lookup_name("__lock_task_sighand");
	if (!zap_page_range_fn || !unmap_kernel_range_fn || !get_vm_area_fn ||
	    !expand_files_fn || !get_files_struct_fn || !put_files_struct_fn ||
	    !can_nice_fn || !lock_sighand_fn)
		return -ENOENT;
	return 0;
}

unsigned long zap_page_range(struct vm_area_struct *vma, unsigned long address,
		unsigned long size, struct zap_details *details)
{
	return zap_page_range_fn(vma, address, size, details);
}

void unmap_kernel_range(unsigned long addr, unsigned long size)
{
	unmap_kernel_range_fn(addr, size);
}

struct vm_struct *get_vm_area(unsigned long size, unsigned long flags)
{
	return get_vm_area_fn(size, flags);
}

int expand_files(struct files_struct *files, int nr)
{
	return expand_files_fn(files, nr);
}

struct files_struct *get_files_struct(struct task_struct *task)
{
	return get_files_struct_fn(task);
}

void put_files_struct(struct files_struct *files)
{
	put_files_struct_fn(files);
}

int can_nice(const struct task_struct *p, const int nice)
{
	return can_nice_fn(p, nice);
}

struct sighand_struct *__lock_task_sighand(struct task_struct *tsk, unsigned long *flags)
{
	return lock_sighand_fn(tsk, flags);
}
