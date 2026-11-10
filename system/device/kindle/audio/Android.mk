LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
LOCAL_MODULE := audio.primary.kindle
LOCAL_MODULE_RELATIVE_PATH := hw
LOCAL_SRC_FILES := audio_kindle.c
LOCAL_CFLAGS := -Wall -Wextra -Wno-unused-parameter
include $(BUILD_SHARED_LIBRARY)
