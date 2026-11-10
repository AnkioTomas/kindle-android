LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := webviewchromium
LOCAL_MODULE_TAGS := optional
LOCAL_SRC_FILES := stub/WebViewStub.java
include $(BUILD_JAVA_LIBRARY)
