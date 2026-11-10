# 放进 AOSP 4.4.4 的 device/kindle/ 后 lunch aosp_kindle-user。
# core_base 含 surfaceflinger。不继承 aosp_base：那条链会编进
# 电话、音乐、图库、浏览器、壁纸、输入法和全部语言。
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_base.mk)
$(call inherit-product-if-exists, frameworks/base/data/fonts/fonts.mk)
$(call inherit-product-if-exists, frameworks/base/data/keyboards/keyboards.mk)

PRODUCT_NAME := aosp_kindle
PRODUCT_DEVICE := kindle
PRODUCT_BRAND := kindle
PRODUCT_MODEL := Kindle
PRODUCT_MANUFACTURER := kindle

PRODUCT_PACKAGES += \
    KindleHome \
    libkindleshim \
    SystemUI \
    Provision

PRODUCT_PROPERTY_OVERRIDES += \
    ro.sf.lcd_density=167 \
    ro.config.low_ram=true \
    ro.kernel.qemu=1 \
    ro.kernel.qemu.gles=0 \
    debug.sf.nobootanimation=0 \
    dalvik.vm.heapstartsize=5m \
    dalvik.vm.heapgrowthlimit=32m \
    dalvik.vm.heapsize=48m \
    persist.sys.timezone=Asia/Shanghai

PRODUCT_COPY_FILES += \
    device/kindle/init.kindle.rc:root/init.kindle.rc \
    device/kindle/keylayout/kindle-input-pt.kl:system/usr/keylayout/kindle-input-pt.kl

PRODUCT_AAPT_PREF_CONFIG := mdpi
PRODUCT_LOCALES := zh_CN
