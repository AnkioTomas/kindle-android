#!/bin/sh
# 装到 Kindle 的用户分区。在 Kindle 上直接跑，或把已挂载的盘符当参数。
#   sh install.sh
#   sh install.sh /Volumes/Kindle
set -e
here=$(cd "$(dirname "$0")" && pwd)
if [ -n "$1" ]; then
	base=$1
elif [ -d /mnt/base-us ]; then
	base=/mnt/base-us
else
	echo "usage: sh install.sh /path/to/kindle/userstore"
	exit 1
fi
[ -d "$base" ] || { echo "no such directory: $base"; exit 1; }
dest=$base/kindle-android
if [ "$here" = "$dest" ]; then
	echo "installed $dest"
	exit 0
fi
rm -rf "$dest"
mkdir -p "$dest"
cp -R "$here"/. "$dest/"
echo "installed $dest"
