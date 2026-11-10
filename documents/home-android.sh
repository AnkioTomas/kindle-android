#!/bin/sh
# Name: Android
# Author: kindle-android
# DontUseFBInk
#
# Scriptlet。拷到 Kindle 的 documents/ 后，书库里出现入口。
( setsid sh /mnt/base-us/android/android.sh home </dev/null >/dev/null 2>&1 & )
