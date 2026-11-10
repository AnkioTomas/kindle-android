-- KT2 / Bourbon：内核不提供 binder，内存 256MB，Android 7 进不去。
-- 这里只保存可见帧、等结束，再原样刷回去。清屏和文字由 eips 完成。
local ffi = require("ffi")

ffi.cdef[[
typedef struct { uint32_t top, left, width, height; } rect;
typedef struct { uint32_t phys, width, height; rect region; } alt;
typedef struct {
	rect region;
	uint32_t waveform, mode, marker, hist_bw, hist_gray;
	int32_t temp;
	uint32_t flags;
	alt altb;
} upd;
int open(const char *path, int flags);
int close(int fd);
int ioctl(int fd, unsigned long req, ...);
void *mmap(void *addr, unsigned long len, int prot, int flags, int fd, long off);
int munmap(void *addr, unsigned long len);
int usleep(unsigned int usec);
long read(int fd, void *buf, unsigned long n);
]]

local SEND = 0x4048462E
local O_RDWR = 2
local O_NONBLOCK = 2048
local PROT_RW = 3
local MAP_SHARED = 1

local function num(path)
	local f = io.open(path)
	if not f then
		return nil
	end
	local s = f:read("*l")
	f:close()
	return tonumber(s)
end

local function log(s)
	local f = io.open("/var/tmp/android/bourbon.log", "a")
	if f then
		f:write(s, "\n")
		f:close()
	end
end

local function refresh(fd, top, width, h, wave)
	local u = ffi.new("upd")
	u.region.top = top
	u.region.left = 0
	u.region.width = width
	u.region.height = h
	u.waveform = wave
	u.mode = 0
	u.marker = 1
	u.temp = 0x1000
	local rc = ffi.C.ioctl(fd, SEND, u)
	log(string.format("refresh %d wave %d y %d h %d", rc, wave, top, h))
	return rc
end

local stride = num("/sys/class/graphics/fb0/stride") or 608
local fd = ffi.C.open("/dev/fb0", O_RDWR)
if fd < 0 then
	log("open fb failed")
	os.exit(1)
end

local var = ffi.new("uint32_t[64]")
ffi.C.ioctl(fd, 0x4600, var)
local xres = tonumber(var[0])
local yres = tonumber(var[1])
local yoff = tonumber(var[5])
if xres == 0 or yres == 0 then
	xres, yres, yoff = 600, 800, 0
end
local bytes = stride * yres
local maplen = stride * (yoff + yres)
local map = ffi.C.mmap(nil, maplen, PROT_RW, MAP_SHARED, fd, 0)
if map == ffi.cast("void *", -1) then
	log("mmap failed")
	os.exit(1)
end
local base = ffi.cast("uint8_t *", map) + yoff * stride
local saved = ffi.new("uint8_t[?]", bytes)
ffi.copy(saved, base, bytes)
log(string.format("saved %dx%d stride %d yoff %d", xres, yres, stride, yoff))

local ready = io.open("/var/tmp/android/bourbon.ready", "w")
ready:write("1\n")
ready:close()

ffi.cdef[[int memcmp(const void *a, const void *b, unsigned long n);]]
local last = ffi.new("uint8_t[?]", bytes)
local lastp = ffi.cast("uint8_t *", last)
ffi.copy(lastp, base, bytes)

local function band()
	if ffi.C.memcmp(base, lastp, bytes) == 0 then
		return -1, -1
	end
	local y0, y1 = -1, -1
	local y = 0
	while y < yres do
		local off = y * stride
		if ffi.C.memcmp(base + off, lastp + off, xres) ~= 0 then
			if y0 < 0 then
				y0 = y
			end
			y1 = y
		end
		y = y + 1
	end
	if y0 < 0 then
		ffi.copy(lastp, base, bytes)
	end
	return y0, y1
end

local function sync_span(y0, y1)
	local y = y0
	while y <= y1 do
		local off = y * stride
		ffi.copy(lastp + off, base + off, stride)
		y = y + 1
	end
end

-- 小块是按钮，看到就用 DU 刷。大块是翻页，灰阶，再等一拍把半帧并掉。
-- 帧缓冲是不缓存的，扫得更勤只会占掉这一颗核。
local tick = 0
local hold = 0
local painted = -10
while true do
	tick = tick + 1
	if tick % 10 == 0 then
		local stop = io.open("/var/tmp/android/bourbon.stop")
		if stop then
			stop:close()
			break
		end
		local poke = io.open("/var/tmp/android/bourbon.refresh")
		if poke then
			poke:close()
			os.remove("/var/tmp/android/bourbon.refresh")
			if refresh(fd, 0, xres, yres, 5) == 0 then
				sync_span(0, yres - 1)
			end
			hold = 0
			painted = tick
		end
	end
	ffi.C.usleep(200000)
	local y0, y1 = band()
	if y0 < 0 then
		hold = 0
	else
		local top = y0 - (y0 % 8)
		local bot = y1 + 7 - (y1 % 8)
		if bot >= yres then
			bot = yres - 1
		end
		local h = bot - top + 1
		-- 工具栏大约几十行。再高就是正文，必须走灰阶，否则字会变成黑白。
		local page = h > 96
		if page then
			hold = hold + 1
		else
			hold = 0
		end
		if page and hold >= 2 and tick - painted >= 1 then
			if refresh(fd, top, xres, h, 5) == 0 then
				sync_span(top, bot)
				painted = tick
				hold = 0
			end
		elseif not page and tick - painted >= 1 then
			if refresh(fd, top, xres, h, 1) == 0 then
				sync_span(top, bot)
				painted = tick
			end
		end
	end
end

ffi.copy(base, saved, bytes)
refresh(fd, 0, xres, yres, 5)
log("restored")
os.exit(0)
