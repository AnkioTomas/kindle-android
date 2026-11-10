# 把本目录放进 AOSP 7.1.1 的 device/kindle/，然后 lunch aosp_kindle-user。
# core_base 含 surfaceflinger。不继承 aosp_base：那条链会编进
# 电话、邮件、日历、浏览器、启动器、设置和全部语言。
# system.prop 由编译系统从本目录自动收进去。
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_base.mk)
$(call inherit-product-if-exists, frameworks/base/data/fonts/fonts.mk)
$(call inherit-product-if-exists, frameworks/base/data/keyboards/keyboards.mk)

PRODUCT_NAME := aosp_kindle
PRODUCT_DEVICE := kindle
PRODUCT_BRAND := kindle
PRODUCT_MODEL := kindle
PRODUCT_MANUFACTURER := kindle

PRODUCT_PACKAGES += \
    KindleHome \
    libkindleshim \
    audio.primary.kindle \
    SystemUI \
    Provision

PRODUCT_PROPERTY_OVERRIDES += \
    ro.sf.lcd_density=300 \
    ro.config.low_ram=true \
    ro.kernel.qemu=1 \
    qemu.gles=0 \
    debug.sf.nobootanimation=1 \
    ro.hardware.audio.primary=kindle \
    dalvik.vm.heapstartsize=4m \
    dalvik.vm.heapgrowthlimit=64m \
    dalvik.vm.heapsize=128m \
    ro.config.max_starting_bg=1 \
    persist.sys.timezone=Asia/Shanghai \
    dalvik.vm.dex2oat-threads=2

PRODUCT_COPY_FILES += \
    device/kindle/init.kindle.rc:root/init.kindle.rc \
    device/kindle/keylayout/kindle-input-pt.kl:system/usr/keylayout/kindle-input-pt.kl

PRODUCT_AAPT_PREF_CONFIG := hdpi
PRODUCT_LOCALES := zh_CN
