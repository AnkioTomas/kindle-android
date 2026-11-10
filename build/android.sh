#!/bin/sh
# 编其中一套系统。两套不能混在同一棵 AOSP 树上。
#   AOSP_ROOT=/path/to/android-4.4.4 sh build/android.sh 4.4
#   AOSP_ROOT=/path/to/android-7.1.1 sh build/android.sh 7
set -e
cd "$(dirname "$0")/.."
api=$1
: "${AOSP_ROOT:?set AOSP_ROOT to the AOSP tree for this API}"
case $api in
4.4) want=4.4 ;;
7) want=7.1 ;;
*) echo "usage: AOSP_ROOT=... sh build/android.sh 4.4|7"; exit 1 ;;
esac
verfile=$AOSP_ROOT/build/core/version_defaults.mk
[ -f "$verfile" ] || { echo "not an AOSP tree: $AOSP_ROOT"; exit 1; }
got=$(sed -n 's/^[[:space:]]*PLATFORM_VERSION := //p' "$verfile" | head -n 1)
case $got in
"$want"*) ;;
*) echo "tree is $got, this script was asked for $want"; exit 1 ;;
esac
dest=$AOSP_ROOT/device/kindle
rm -rf "$dest"
mkdir -p "$dest"
cp -R system/device/kindle/. "$dest/"
if [ "$api" = 4.4 ]; then
	rm -rf "$dest/audio"
	cp system/target/4.4/BoardConfig.mk "$dest/BoardConfig.mk"
	cp system/target/4.4/aosp_kindle.mk "$dest/aosp_kindle.mk"
	cp system/target/4.4/init.kindle.rc "$dest/init.kindle.rc"
	cp system/target/4.4/system.prop "$dest/system.prop"
	wv=$AOSP_ROOT/frameworks/webview/chromium
	cp system/target/4.4/webviewchromium.mk "$wv/Android.mk"
	mkdir -p "$wv/stub"
	cp system/target/4.4/WebViewStub.java "$wv/stub/WebViewStub.java"
	# 4.4.4_r2 names the droiddoc module api-stubs and never builds
	# android_stubs_current. SDK apps compile against the prebuilt
	# android.jar (sdk_vcurrent), which contains java.lang. framework.jar does not.
	sed -i \
		-e 's/java-lib-files,android_stubs_current/java-lib-files,sdk_vcurrent/' \
		-e 's/java-lib-files,framework/java-lib-files,sdk_vcurrent/' \
		"$AOSP_ROOT/build/core/base_rules.mk"
	sed -i \
		-e 's/LOCAL_JAVA_LIBRARIES := android_stubs_current /LOCAL_JAVA_LIBRARIES := sdk_vcurrent /' \
		-e 's/LOCAL_JAVA_LIBRARIES := framework /LOCAL_JAVA_LIBRARIES := sdk_vcurrent /' \
		"$AOSP_ROOT/build/core/java.mk" \
		"$AOSP_ROOT/build/core/droiddoc.mk"
	# external/chromium is not in this tree. libstagefright already
	# dlopens libstagefright_chromium_http.so and continues without it.
	sed -i '/libstagefright_chromium_http/d' \
		"$AOSP_ROOT/build/target/product/core_base.mk"
fi
if [ "$api" = 7 ]; then
	# Jack 4.8 speaks TLS 1.0. JDK 8u372 disables it, so the server
	# comes up and the client immediately fails the handshake.
	# prebuilts/sdk/tools/jack uses $USER with nounset. Docker does not set it.
	export USER="${USER:-root}"
	sec=${JAVA_HOME:-}/jre/lib/security/java.security
	if [ -f "$sec" ]; then
		sed -i 's/SSLv3, TLSv1, TLSv1.1, /SSLv3, /' "$sec"
	fi
	# 7.1 names the droiddoc module api-stubs and never builds
	# android_stubs_current. Jack still wants its classes.dex.toc.
	# SDK=current apps compile against framework instead.
	sed -i \
		-e 's/java-lib-files, *android_stubs_current/java-lib-files,framework/' \
		-e 's/java-lib-files, *android_system_stubs_current/java-lib-files,framework/' \
		-e 's/java-lib-files, *android_test_stubs_current/java-lib-files,framework/' \
		-e 's/jack-lib-files, *android_stubs_current/jack-lib-files,framework/' \
		-e 's/jack-lib-files, *android_system_stubs_current/jack-lib-files,framework/' \
		-e 's/jack-lib-files, *android_test_stubs_current/jack-lib-files,framework/' \
		-e 's/LOCAL_JAVA_LIBRARIES := android_stubs_current /LOCAL_JAVA_LIBRARIES := framework /' \
		-e 's/LOCAL_JAVA_LIBRARIES := android_system_stubs_current /LOCAL_JAVA_LIBRARIES := framework /' \
		-e 's/LOCAL_JAVA_LIBRARIES := android_test_stubs_current /LOCAL_JAVA_LIBRARIES := framework /' \
		"$AOSP_ROOT/build/core/java.mk" \
		"$AOSP_ROOT/build/core/java_common.mk" \
		"$AOSP_ROOT/build/core/droiddoc.mk" \
		"$AOSP_ROOT/dalvik/dx/Android.mk"
fi
if [ -n "$JOBS" ]; then
	jobs=$JOBS
elif command -v nproc >/dev/null 2>&1; then
	jobs=$(nproc)
else
	jobs=$(sysctl -n hw.ncpu)
fi
# user, not userdebug: userdebug pulls target-tests into droidcore.
exec bash -c 'cd "$1" && source build/envsetup.sh && lunch aosp_kindle-user && make -j"$2"' _ "$AOSP_ROOT" "$jobs"
