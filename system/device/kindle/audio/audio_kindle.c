/* 主音频 HAL。PCM 16-bit 44100 立体声写到 /dev/kfb/audio.fifo。
 * 第一次写之前往 /dev/kfb/kfb.fifo 送一行 audio，宿主才把 gst 接上。
 * 对着 android-7.1.1_r61 的 hardware/libhardware/include/hardware/audio.h。
 */
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include <hardware/audio.h>
#include <hardware/hardware.h>

#define RATE 44100
#define FRAME 4

struct kindle_out {
	struct audio_stream_out stream;
	int fd;
	int started;
	uint64_t frames;
};

struct kindle_dev {
	struct audio_hw_device device;
	float volume;
};

static int notify_audio(void)
{
	int fd;

	fd = open("/dev/kfb/kfb.fifo", O_WRONLY | O_NONBLOCK);
	if (fd < 0)
		return -1;
	if (write(fd, "audio\n", 6) != 6) {
		close(fd);
		return -1;
	}
	close(fd);
	return 0;
}

static void out_open_fifo(struct kindle_out *out)
{
	int i;

	if (out->fd >= 0 || out->started)
		return;
	if (access("/dev/kfb/audio.fifo", F_OK) != 0) {
		out->started = 1;
		return;
	}
	for (i = 0; i < 20 && out->fd < 0; i++) {
		if (i == 0 || i == 10)
			notify_audio();
		out->fd = open("/dev/kfb/audio.fifo", O_WRONLY | O_NONBLOCK);
		if (out->fd < 0)
			usleep(50000);
	}
	out->started = 1;
}

static uint32_t out_get_sample_rate(const struct audio_stream *stream)
{
	(void)stream;
	return RATE;
}

static int out_set_sample_rate(struct audio_stream *stream, uint32_t rate)
{
	(void)stream;
	return rate == RATE ? 0 : -EINVAL;
}

static size_t out_get_buffer_size(const struct audio_stream *stream)
{
	(void)stream;
	return RATE / 50 * FRAME;
}

static audio_channel_mask_t out_get_channels(const struct audio_stream *stream)
{
	(void)stream;
	return AUDIO_CHANNEL_OUT_STEREO;
}

static audio_format_t out_get_format(const struct audio_stream *stream)
{
	(void)stream;
	return AUDIO_FORMAT_PCM_16_BIT;
}

static int out_set_format(struct audio_stream *stream, audio_format_t format)
{
	(void)stream;
	return format == AUDIO_FORMAT_PCM_16_BIT ? 0 : -EINVAL;
}

/* AudioFlinger 在两段声音之间会 standby。关掉 fifo 会让宿主的 gst 读到 EOF 退出，
 * 下一次写的时候它可能还活着，宿主就不会再拉起，声音就没了。流还在就一直占着 fifo。 */
static int out_standby(struct audio_stream *stream)
{
	(void)stream;
	return 0;
}

static int out_dump(const struct audio_stream *stream, int fd)
{
	(void)stream;
	(void)fd;
	return 0;
}

static audio_devices_t out_get_device(const struct audio_stream *stream)
{
	(void)stream;
	return AUDIO_DEVICE_OUT_SPEAKER;
}

static int out_set_device(struct audio_stream *stream, audio_devices_t device)
{
	(void)stream;
	(void)device;
	return 0;
}

static char *out_get_parameters(const struct audio_stream *stream, const char *keys)
{
	(void)stream;
	(void)keys;
	return strdup("");
}

static int out_set_parameters(struct audio_stream *stream, const char *kv)
{
	(void)stream;
	(void)kv;
	return 0;
}

static int out_add_effect(const struct audio_stream *stream, effect_handle_t effect)
{
	(void)stream;
	(void)effect;
	return 0;
}

static int out_remove_effect(const struct audio_stream *stream, effect_handle_t effect)
{
	(void)stream;
	(void)effect;
	return 0;
}

static uint32_t out_get_latency(const struct audio_stream_out *stream)
{
	(void)stream;
	return 50;
}

static int out_set_volume(struct audio_stream_out *stream, float left, float right)
{
	(void)stream;
	(void)left;
	(void)right;
	return 0;
}

static ssize_t out_write(struct audio_stream_out *stream, const void *buffer, size_t bytes)
{
	struct kindle_out *out = (struct kindle_out *)stream;
	const char *p = buffer;
	size_t left = bytes;

	out_open_fifo(out);
	while (out->fd >= 0 && left > 0) {
		ssize_t n = write(out->fd, p, left);
		if (n < 0) {
			if (errno == EAGAIN)
				break;
			close(out->fd);
			out->fd = -1;
			break;
		}
		p += n;
		left -= n;
	}
	out->frames += (bytes / FRAME);
	return bytes;
}

static int out_get_render_position(const struct audio_stream_out *stream, uint32_t *frames)
{
	const struct kindle_out *out = (const struct kindle_out *)stream;
	*frames = (uint32_t)out->frames;
	return 0;
}

static int out_get_next_write_timestamp(const struct audio_stream_out *stream, int64_t *ts)
{
	(void)stream;
	(void)ts;
	return -EINVAL;
}

static int out_set_callback(struct audio_stream_out *stream, stream_callback_t cb, void *cookie)
{
	(void)stream;
	(void)cb;
	(void)cookie;
	return -ENOSYS;
}

static int out_pause(struct audio_stream_out *stream)
{
	(void)stream;
	return -ENOSYS;
}

static int out_resume(struct audio_stream_out *stream)
{
	(void)stream;
	return -ENOSYS;
}

static int out_drain(struct audio_stream_out *stream, audio_drain_type_t type)
{
	(void)stream;
	(void)type;
	return 0;
}

static int out_flush(struct audio_stream_out *stream)
{
	(void)stream;
	return 0;
}

static int out_get_presentation_position(const struct audio_stream_out *stream,
		uint64_t *frames, struct timespec *ts)
{
	const struct kindle_out *out = (const struct kindle_out *)stream;
	*frames = out->frames;
	clock_gettime(CLOCK_MONOTONIC, ts);
	return 0;
}

static int adev_close(hw_device_t *device)
{
	free(device);
	return 0;
}

static uint32_t adev_supported(const struct audio_hw_device *dev)
{
	(void)dev;
	return AUDIO_DEVICE_OUT_SPEAKER;
}

static int adev_init_check(const struct audio_hw_device *dev)
{
	(void)dev;
	return 0;
}

static int adev_set_voice_volume(struct audio_hw_device *dev, float volume)
{
	(void)dev;
	(void)volume;
	return 0;
}

static int adev_set_master_volume(struct audio_hw_device *dev, float volume)
{
	((struct kindle_dev *)dev)->volume = volume;
	return 0;
}

static int adev_get_master_volume(struct audio_hw_device *dev, float *volume)
{
	*volume = ((struct kindle_dev *)dev)->volume;
	return 0;
}

static int adev_set_mode(struct audio_hw_device *dev, audio_mode_t mode)
{
	(void)dev;
	(void)mode;
	return 0;
}

static int adev_set_mic_mute(struct audio_hw_device *dev, bool state)
{
	(void)dev;
	(void)state;
	return 0;
}

static int adev_get_mic_mute(const struct audio_hw_device *dev, bool *state)
{
	(void)dev;
	*state = 0;
	return 0;
}

static int adev_set_parameters(struct audio_hw_device *dev, const char *kv)
{
	(void)dev;
	(void)kv;
	return 0;
}

static char *adev_get_parameters(const struct audio_hw_device *dev, const char *keys)
{
	(void)dev;
	(void)keys;
	return strdup("");
}

static size_t adev_get_input_buffer_size(const struct audio_hw_device *dev,
		const struct audio_config *config)
{
	(void)dev;
	(void)config;
	return 0;
}

static void fill_out(struct kindle_out *out)
{
	out->fd = -1;
	out->stream.common.get_sample_rate = out_get_sample_rate;
	out->stream.common.set_sample_rate = out_set_sample_rate;
	out->stream.common.get_buffer_size = out_get_buffer_size;
	out->stream.common.get_channels = out_get_channels;
	out->stream.common.get_format = out_get_format;
	out->stream.common.set_format = out_set_format;
	out->stream.common.standby = out_standby;
	out->stream.common.dump = out_dump;
	out->stream.common.get_device = out_get_device;
	out->stream.common.set_device = out_set_device;
	out->stream.common.set_parameters = out_set_parameters;
	out->stream.common.get_parameters = out_get_parameters;
	out->stream.common.add_audio_effect = out_add_effect;
	out->stream.common.remove_audio_effect = out_remove_effect;
	out->stream.get_latency = out_get_latency;
	out->stream.set_volume = out_set_volume;
	out->stream.write = out_write;
	out->stream.get_render_position = out_get_render_position;
	out->stream.get_next_write_timestamp = out_get_next_write_timestamp;
	out->stream.set_callback = out_set_callback;
	out->stream.pause = out_pause;
	out->stream.resume = out_resume;
	out->stream.drain = out_drain;
	out->stream.flush = out_flush;
	out->stream.get_presentation_position = out_get_presentation_position;
}

static int adev_open_output_stream(struct audio_hw_device *dev,
		audio_io_handle_t handle, audio_devices_t devices, audio_output_flags_t flags,
		struct audio_config *config, struct audio_stream_out **stream_out,
		const char *address)
{
	struct kindle_out *out;

	(void)dev;
	(void)handle;
	(void)devices;
	(void)flags;
	(void)address;
	out = calloc(1, sizeof *out);
	if (!out)
		return -ENOMEM;
	fill_out(out);
	config->sample_rate = RATE;
	config->format = AUDIO_FORMAT_PCM_16_BIT;
	config->channel_mask = AUDIO_CHANNEL_OUT_STEREO;
	*stream_out = &out->stream;
	return 0;
}

static void adev_close_output_stream(struct audio_hw_device *dev, struct audio_stream_out *stream)
{
	struct kindle_out *out = (struct kindle_out *)stream;

	(void)dev;
	if (out->fd >= 0)
		close(out->fd);
	free(out);
}

static int adev_open_input_stream(struct audio_hw_device *dev,
		audio_io_handle_t handle, audio_devices_t devices, struct audio_config *config,
		struct audio_stream_in **stream_in, audio_input_flags_t flags,
		const char *address, audio_source_t source)
{
	(void)dev;
	(void)handle;
	(void)devices;
	(void)config;
	(void)stream_in;
	(void)flags;
	(void)address;
	(void)source;
	return -ENOSYS;
}

static void adev_close_input_stream(struct audio_hw_device *dev, struct audio_stream_in *stream)
{
	(void)dev;
	(void)stream;
}

static int adev_dump(const struct audio_hw_device *dev, int fd)
{
	(void)dev;
	(void)fd;
	return 0;
}

static int adev_set_master_mute(struct audio_hw_device *dev, bool mute)
{
	(void)dev;
	(void)mute;
	return 0;
}

static int adev_get_master_mute(struct audio_hw_device *dev, bool *mute)
{
	(void)dev;
	*mute = 0;
	return 0;
}

static audio_patch_handle_t patch_id = 1;

static int adev_create_audio_patch(struct audio_hw_device *dev,
		unsigned int num_sources, const struct audio_port_config *sources,
		unsigned int num_sinks, const struct audio_port_config *sinks,
		audio_patch_handle_t *handle)
{
	(void)dev;
	(void)num_sources;
	(void)sources;
	(void)num_sinks;
	(void)sinks;
	*handle = patch_id++;
	return 0;
}

static int adev_release_audio_patch(struct audio_hw_device *dev, audio_patch_handle_t handle)
{
	(void)dev;
	(void)handle;
	return 0;
}

static int adev_get_audio_port(struct audio_hw_device *dev, struct audio_port *port)
{
	(void)dev;
	(void)port;
	return -EINVAL;
}

static int adev_set_audio_port_config(struct audio_hw_device *dev,
		const struct audio_port_config *config)
{
	(void)dev;
	(void)config;
	return 0;
}

static int adev_open(const hw_module_t *module, const char *name, hw_device_t **device)
{
	struct kindle_dev *dev;

	if (strcmp(name, AUDIO_HARDWARE_INTERFACE) != 0)
		return -EINVAL;
	dev = calloc(1, sizeof *dev);
	if (!dev)
		return -ENOMEM;
	dev->volume = 1.f;
	dev->device.common.tag = HARDWARE_DEVICE_TAG;
	dev->device.common.version = AUDIO_DEVICE_API_VERSION_3_0;
	dev->device.common.module = (struct hw_module_t *)module;
	dev->device.common.close = adev_close;
	dev->device.get_supported_devices = adev_supported;
	dev->device.init_check = adev_init_check;
	dev->device.set_voice_volume = adev_set_voice_volume;
	dev->device.set_master_volume = adev_set_master_volume;
	dev->device.get_master_volume = adev_get_master_volume;
	dev->device.set_mode = adev_set_mode;
	dev->device.set_mic_mute = adev_set_mic_mute;
	dev->device.get_mic_mute = adev_get_mic_mute;
	dev->device.set_parameters = adev_set_parameters;
	dev->device.get_parameters = adev_get_parameters;
	dev->device.get_input_buffer_size = adev_get_input_buffer_size;
	dev->device.open_output_stream = adev_open_output_stream;
	dev->device.close_output_stream = adev_close_output_stream;
	dev->device.open_input_stream = adev_open_input_stream;
	dev->device.close_input_stream = adev_close_input_stream;
	dev->device.dump = adev_dump;
	dev->device.set_master_mute = adev_set_master_mute;
	dev->device.get_master_mute = adev_get_master_mute;
	dev->device.create_audio_patch = adev_create_audio_patch;
	dev->device.release_audio_patch = adev_release_audio_patch;
	dev->device.get_audio_port = adev_get_audio_port;
	dev->device.set_audio_port_config = adev_set_audio_port_config;
	*device = &dev->device.common;
	return 0;
}

static struct hw_module_methods_t hal_methods = {
	.open = adev_open,
};

struct audio_module HAL_MODULE_INFO_SYM = {
	.common = {
		.tag = HARDWARE_MODULE_TAG,
		.module_api_version = AUDIO_MODULE_API_VERSION_0_1,
		.hal_api_version = HARDWARE_HAL_API_VERSION,
		.id = AUDIO_HARDWARE_MODULE_ID,
		.name = "Kindle audio",
		.author = "kindle-android",
		.methods = &hal_methods,
	},
};
