#!/bin/sh
# 打出用户拷到 Kindle 用户分区里的安装包。
#   sh build/pack.sh
set -e
cd "$(dirname "$0")/.."
ver=$(cat VERSION)
stage=$(mktemp -d)
name=kindle-android-$ver
out=dist/$name.tar.gz
mkdir -p "$stage/$name" dist
cp android.sh stop.sh ashell.sh VERSION "$stage/$name/"
cp -R lib platform src system build "$stage/$name/"
rm -rf "$stage/$name/build/pack.sh"
cp build/install.sh "$stage/$name/install.sh"
chmod 755 "$stage/$name/install.sh" "$stage/$name/android.sh" "$stage/$name/stop.sh" "$stage/$name/build/android.sh"
mkdir -p "$stage/$name/bin"
if [ -f bin/binder.ko ]; then
	cp bin/binder.ko bin/ashmem.ko "$stage/$name/bin/"
fi
if [ -d images ]; then
	cp -R images "$stage/$name/"
fi
tar -C "$stage" -czf "$out" "$name"
rm -rf "$stage"
echo "$out"
