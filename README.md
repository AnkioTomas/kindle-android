# kindle-android

在已越狱的 Kindle 上用 Linux 命名空间跑一个精简 Android，让阅读应用直接画到墨水屏上。

版本：`0.1.0`。目标机器是 Paperwhite 5 这一档：用户分区是 FAT，内存不到 700MB。

## 跑起来需要的东西

Kindle 固件 5.18 或更新，已经越狱。把本仓库放到 Kindle 的 `/mnt/base-us/android`。Scriptlet 用户再把 `documents/home-android.sh` 拷到 `documents/`。

`bin/` 里要有这些 ARM 程序，仓库不带二进制：

| 文件 | 来源 |
|---|---|
| `pivot_init` `kafstub` `loopdio` `slirpfwd` `keyinject` | `CROSS=arm-linux-gnueabihf- sh src/build.sh` |
| `fbink` | [FBInk](https://github.com/NiLuJe/FBInk) 的 Kindle 构建 |
| `slirp4netns` | 上游 v1.3.x 的 armv7 静态包 |
| `libkindleshim.so` | `system/` 编出来的兼容库，放 `bin/`，或已经在系统镜像里。没有它启动会停在提示画面 |
| `images/system.sqfs` 或 `system.tar.gz` | 自己编的 Android 7 根文件系统，第一次启动解开 |

可选：`bin/filebrowser`（linux-armv7），设置里 `FILEBROWSER=1` 才用。阅读 APK 放 `apps/`，装成功就删掉。

## 启动链

`android.sh` 是唯一入口。顺序是固定的：

1. FAT 上建/挂 `system/android-sys.img` 和 `system/android-data.img`，并把承载 FAT 的 loop 改成 direct-io。
2. `pivot_init --detach` 脱离书库提权留下的 framework 身份。
3. 停 Kindle 绘制。内存不到 700MB 时停掉整个 `lab126_gui`，`kafstub` 冒充 `com.lab126.kaf` 的 `frameworkStarted`，否则 powerd 不处理电源键。
4. 把 `libkindleshim.so` 拷进 tmpfs。优先 `bin/`，镜像里那份非空也行。
5. 第一次把系统镜像解开，根改只读。
6. `unshare -m -u -i -n -p`，绑上 binder（用宿主空着的 `vndbinder`）、帧缓冲、触摸、`/data`，然后 `pivot_init` 执行 `/init --second-stage`。
7. `slirp4netns` 给容器 `eth0`，网段 `10.157.43.0/24`，客户机 `.15`。
8. 看门狗、屏保、按需装 APK。

回到 Kindle 走 `stop.sh`：杀掉容器 init，撤端口，卸镜像，还原 loop，拉回界面。运行期间 USB 只充电。

冻结没有做。FAT 镜像退出时必须卸掉，否则电脑认不出 U 盘。默认 `RETURN_MODE=off`，回到 Kindle 就是关机。

## `/dev/kfb` 契约

容器里的 `/dev/kfb` 是宿主的 tmpfs。兼容库和桌面只看这些文件。

- `geom`：`宽 高`
- `epd.conf`：第一行 `抖动 动画 步数 局部波形 彩色`；第二行 256 个 gamma；第三行 `隔几页全刷 整页波形`。波形：DU=1，GC16=2，REAGL=4，A2=6，AUTO=257
- `epd.conf.<包名>`：这个应用自己的一份
- `gestures`：7 个动作编号、左右半屏的滑动模式（0 无、1 亮度、2 色温）、双指窗口毫秒、角落按住毫秒。动作顺序是 `none clear invert back home switch menu light wifi sleep exit bt panel`
- `kfb.fifo`：兼容库写给宿主。`touch`、`cmd:suspend`、`cmd:fl_step=+1`、`cmd:warmth_step=-1`、`cmd:fl_set=N`、`cmd:warmth_set=N`、`cmd:fl_toggle`、`cmd:status`、`cmd:bt_toggle`、`cmd:wifi_toggle`、`cmd:fl_auto=0|1`、`audio`、`cmd:userstore`、`cmd:userstore_resize=MB`
- `epd.fifo`：宿主写给兼容库。`redraw`、`rows y1 y2`、`reload`
- `ctl/app`：要打开的包名，或 `包名/类名`，或 `home`
- `ctl/exit` `ctl/stop` `ctl/restart` `ctl/diag` `ctl/settings.new` `ctl/sleep` `ctl/shown` `ctl/invert` `ctl/nogestures` `ctl/warmth`
- `ctl/status`：宿主回给桌面的电量、时间、无线、亮度
- `audio.fifo`：`AUDIO=1` 时才有。音频 HAL 写 s16le 44100 立体声，宿主用 Kindle 的 gst 送到蓝牙
- `keys`：兼容库写 `back` `home` `menu` `switch`。宿主的 `keyinject` 注进虚拟键盘，再绑到容器的 `/dev/input/event3`。容器自己的 `/dev` 是私有 tmpfs，在里面建 uinput 节点安卓看不见

`libkindleshim.so` 只在 surfaceflinger 里刷 `/dev/epd`（宿主 `/dev/fb0`）。gamma 不改像素，翻页滑动不下发。桌面包名是 `com.kindle.home`，读 `ctl/app`。

## 系统

Kindle 专属的源码在 `system/device/kindle/`。AOSP 7.1.1 本身不在这个仓库里。

放进一份 `android-7.1.1_r61` 树：

```text
system/device/kindle/  →  device/kindle/
```

然后 `source build/envsetup.sh && lunch aosp_kindle-userdebug`。产物：

- `libkindleshim.so`，给 `bin/`，或留在镜像的 `/system/lib/`
- `audio.primary.kindle.so`
- `KindleHome.apk`，包名 `com.kindle.home`
- 根上的 `init.kindle.rc`。打包时根和 `/system` 要在同一个文件系统里，启动器把这个目录当容器根

框架、WebView、拼音输入法、`libGLES_android.so` 的 swiftshader 补丁都没有重写。

内核命令行由启动器写成 `androidboot.hardware=kindle androidboot.zygote=zygote32 androidboot.wifiip=<地址或 off>`。镜像里的 `/system/lib/libkindleshim.so` 可以是空文件，启动器会把 tmpfs 上的那份绑上去；文件本身必须存在，绑定才成功。

## 说明

兼容库使用自己编译的明文 `libkindleshim.so`。

`kafstub` 只做一件事：`dlopen("liblipc.so")`，`LipcOpen("com.lab126.kaf")`，注册 `frameworkStarted` 读出来是 1，然后 `pause`。getter 的第三个参数是写出的 int。

`pivot_init` 不做 seccomp。冻结没有做。这套系统源码没有在 Kindle 上编过，也没有启动过。
