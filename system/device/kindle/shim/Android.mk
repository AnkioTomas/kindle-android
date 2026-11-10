LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
LOCAL_MODULE := libkindleshim
LOCAL_SRC_FILES := kindleshim.c
LOCAL_CFLAGS := -Wall -Wextra -O2
include $(BUILD_SHARED_LIBRARY)
