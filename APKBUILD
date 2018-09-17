# Contributor: Kenneth Shaw <kenneth.shaw@knq.io>
# Maintainer: Kenneth Shaw <kenneth.shaw@knq.io>
chromium=/chromium/src
pkgname=headless-shell
pkgrel=0
pkgver=71.0.3554.1
pkgdesc="chromium headless-shell"
url="https://chromium.org"
arch="x86_64"
license="BSD"
depends="eudev-libs ttf-opensans ca-certificates"
depends_dev=""
makedepends="$depends_dev
	alsa-lib-dev
	bash
	binutils-gold
	bison
	flex
	bsd-compat-headers
	bzip2-dev
	cairo-dev
	clang>6.0
	clang-dev>6.0
	cups-dev
	dbus-glib-dev
	eudev-dev
	ffmpeg-dev
	findutils
	flac-dev
	freetype-dev
	gnutls-dev
	gperf
	gtk+3.0-dev
	gzip
	harfbuzz-dev
	hunspell-dev
	hwdata-usb
	jpeg-dev
	jsoncpp-dev
	krb5-dev
	libbsd-dev
	libcap-dev
	libelf-dev
	libevent-dev
	libexif-dev
	libgcrypt-dev
	libgnome-keyring-dev
	libjpeg-turbo-dev
	libpng-dev
	libusb-dev
	libwebp-dev
	libxcomposite-dev
	libxcursor-dev
	libxinerama-dev
	libxml2-dev
	libxrandr-dev
	libxscrnsaver-dev
	libxslt-dev
	libxtst-dev
	linux-headers
	mesa-dev
	mesa-dev
	minizip-dev
	ninja
	nodejs
	nss-dev
	opus-dev
	paxmark
	pciutils-dev
	perl
	python2
	re2-dev
	snappy-dev
	speex-dev
	sqlite-dev
	yasm
	zlib-dev
	"
install=""
options=suid
subpackages=""
source="
	default-pthread-stacksize.patch
	musl-fixes.patch
	musl-fixes-breakpad.patch
	musl-hacks.patch
	musl-libc++.patch
	musl-sandbox.patch
	no-execinfo.patch
	no-mallinfo.patch
	resolver.patch
	swiftshader.patch
	secure_getenv.patch
	chromium-clang-r2.patch

	chromium-use-alpine-target.patch
	chromium-remove-unknown-clang-warnings.patch
	chromium-gcc-r1.patch
	chromium-skia-harmony.patch
	chromium-cors-string-r0.patch
	chromium-libjpeg-r0.patch
	chromium-libwebp-shim-r0.patch
	media-base.patch
	musl-crashpad.patch
	chromium-gcc.patch
	"

if [ -n "$DEBUG" ]; then
	_buildtype=Debug
	_is_debug=true
else
	_buildtype=Release
	_is_debug=false
fi

builddir=$chromium/out/$pkgname-$_buildtype

prepare() {
	mkdir -p "$builddir"

	cd "$chromium"

	find headless -type f -iname \*.cc -exec \
		perl -pi -e 's/"HeadlessChrome"/"Chrome"/' {} \;

#	local i
#	for i in $source; do
#		case $i in
#		*.patch) msg $i; patch -p0 -i "$srcdir"/$i;;
#		esac
#	done

	# https://groups.google.com/a/chromium.org/d/topic/chromium-packagers/9JX1N2nf4PU/discussion
	touch chrome/test/data/webui/i18n_process_css_test.html
	# Use the file at run time instead of effectively compiling it in
	sed 's|//third_party/usb_ids/usb.ids|/usr/share/hwdata/usb.ids|g' \
		-i device/usb/BUILD.gn

	mkdir -p third_party/node/linux/node-linux-x64/bin
	rm -f third_party/node/linux/node-linux-x64/bin/node
	ln -s /usr/bin/node third_party/node/linux/node-linux-x64/bin/node

	# reusable system library settings
	local use_system="
		flac
		fontconfig
		freetype
		harfbuzz-ng
		libdrm
		libevent
		libjpeg
		libpng
		libwebp
		libxml
		libxslt
		opus
		re2
		snappy
		yasm
		"
	for _lib in ${use_system} libjpeg_turbo; do
		msg "Removing buildscripts for system provided $_lib"
		find -type f -path "*third_party/$_lib/*" \
			\! -path "*third_party/$_lib/chromium/*" \
			\! -path "*third_party/$_lib/google/*" \
			\! -path './base/third_party/icu/*' \
			\! -path './third_party/pdfium/third_party/freetype/include/pstables.h' \
			\! -path './third_party/yasm/run_yasm.py' \
			\! -regex '.*\.\(gn\|gni\|isolate\|py\)' \
			-delete
	done

	msg "Replacing gn files"
	python build/linux/unbundle/replace_gn_files.py --system-libraries \
		${use_system}
	third_party/libaddressinput/chromium/tools/update-strings.py
}

build() {
	cd "$chromium"

	export CC=clang
	export CXX=clang++

	msg "Configuring build"
	echo 'import("//build/args/headless.gn")

is_debug='$_is_debug'

symbol_level=0
enable_nacl=false
use_jumbo_build=true
remove_webcore_debug_symbols=true
headless_use_embedded_resources=true

clang_use_chrome_plugins=false
custom_toolchain="//build/toolchain/linux/unbundle:default"
gold_path="/usr/bin/ld.gold"
host_toolchain="//build/toolchain/linux/unbundle:default"

icu_use_data_file=true
is_clang=true
linux_use_bundled_binutils=false
proprietary_codecs=false

treat_warnings_as_errors=false
use_allocator="none"
use_allocator_shim=false
use_custom_libcxx=false
use_gnome_keyring=false
use_gold=false
use_lld=false
use_pulseaudio=false
use_sysroot=false
use_system_harfbuzz=true
' > "$builddir"/args.gn

	# generate configs
	AR="ar" CC="$CC" CXX="$CXX" LD="$CXX" NM=/usr/bin/nm \
		gn gen out/$pkgname-$_buildtype

	# build
	ninja -C out/$pkgname-$_buildtype headless_shell chrome_sandbox
}

package() {
	cd "$builddir"

	install -Dm755 headless_shell "$pkgdir"/usr/lib/$pkgname/headless-shell
	paxmark -m "$pkgdir"/usr/lib/$pkgname/headless-shell
	install -Dm4755 chrome_sandbox "$pkgdir"/usr/lib/$pkgname/chrome-sandbox
	install -m644 icudtl.dat "$pkgdir"/usr/lib/$pkgname/icudtl.dat

	for pak in *.pak; do
		install -Dm644 $pak "$pkgdir"/usr/lib/$pkgname/$pak
	done

	install -Dm755 "$srcdir"/chromium-launcher.sh \
		"$pkgdir"/usr/lib/$pkgname/chromium-launcher.sh

	cp -a locales "$pkgdir"/usr/lib/$pkgname/

	mkdir -p "$pkgdir"/usr/bin
	cd "$pkgdir"/usr/bin
	ln -sf /usr/lib/$pkgname/headless-shell headless-shell
}

sha512sums="05fb6d9434565a7a73f5c18d470ae600bf4afbe15d0e4a7c2770bf2596a0bd2788cdfeb37e0b566fc3d26ff2d0791b70488b2c184e3286cff5a1fa25e17582cd  default-pthread-stacksize.patch
245a5bf4c0881851482561830d9241ad8b3061d2e2596916c2efbdeaf41b96f5a6181183442b3a33aac53fefb3faf7c327258e051141d778ae6fa5b48b98969c  musl-fixes.patch
90efbc89151c77f32434364dcbaabaf9d9a207f4a77f147cd51b3fe100832fbfb3a9fb665303a79a3d788e400f4f41890de202ccbb7bd1fc6252e33c6e74e429  musl-fixes-breakpad.patch
507a8db2317f1f6ec18dec6cb5894b716e9b2542b58887bab9319bc6d4c66fe4a4d09b200ca8e3f11b32e380b282442a27e7a1b358d3c25eef0fa7655e9dc134  musl-hacks.patch
95ead57f7338649351948d100e32e5ec1eeadb02bffa136ff15c6c515eceb8013c444be092d777c1b62b945bfb83b97778ba4d3a0ccc2d7c2c9a0a8cd8ee0f01  musl-libc++.patch
9b75d6ac720d1b8ddc597f0f472bc400ff866a733f12b3a4cd3e7e18e724549c5f8e056c7e0d0462ef083bff5e677f8cef6b89b22f4740a40ad6398978269373  musl-sandbox.patch
0c413940a26c3823213724036d217f43a7de9bca4ae026c5f56d4280800cc7dd4a5cf6efea98dbb102513eda6c29ceae20debb9b938b0fb61628822ecdec0799  no-execinfo.patch
db7f676d3476820c29f234b1f8f17a74e82b72d67fc727c715307734fd238e3cb0f99d8b5320d45f820b62c01163283c4829caa37afd6a9ca7592a54d3c65819  no-mallinfo.patch
6833054ef89da20c0de63faac2f87ff250b5aca3ac785fc404da4a9e03c4e00df9d7da009788e611d113cdf3be2ba50f933d85d6baf20f2df6a3711cceff5152  resolver.patch
6b0812725a0fc562527f3556dc4979fec72d1ba92f26a5e78ff2016c39bb2c155a0ff95fc22101f9c097d14b84182d6615276f4247f60ae7833ab45da8366e6d  swiftshader.patch
de2d6ebc75d0496a9424ea6c025b052d6d59f38477338b0e2a5c21ccec11e774244fd5d340195c523f7a3c02ccfd8ac81486958008bc8b221c848dfa2c71bd50  secure_getenv.patch
38670c9bdc87b3779593eab141ac23741fa47c774ba491f273239a453566979583e352b032caf350ed485bbc006addca0f689b8c439646c2d37e28e3f3ea476c  chromium-clang-r2.patch
246c43a0ab557671119ebc4ecb292925ebfee25312fb50e739a179dc085d23b9623bec2d7baecdd37ebd9318f8770664f20c12de6383def74cd89b7845d149ce  chromium-use-alpine-target.patch
838892a2873145f96659aade410c0b48a03b6e95bdfc3ed5bb88868792caca327ae6843020a4ca209693445831a4a0ad1b0e4f195851b60812a129aa7ff2bf7c  chromium-remove-unknown-clang-warnings.patch
6e2bcbed44786c6c0d3beda935269f30fdcdf07c400defa6bf73f8359a60b1d59cc2f80dbc106be651a535635995641321d9e524b18919d3975bd6008a641d59  chromium-gcc-r1.patch
cbd99d51178fa5c2c3dee1eb4990240ca2ff829cee9151384e36bc3c634698c0ecaf9b51c99e901f38d0a37eef7187fe5ad39b9b7f528f7a9066a855a0c6e49f  chromium-skia-harmony.patch
e2df9816ce01a8175ae45682f48805dd3ab55154a0e9e7b1b5edabd8584f4326bfa25ad7f94dc174c968e72183fff1416e50e2d75671b17b52f2337c16d6c605  chromium-cors-string-r0.patch
30e641d99c804740e18e2c1541907a209a8b54aedb01089473d1f5df721bf55f105400fa7aa2a75bc489f59e740657e79408555395d3cd77d13d15c1569b505d  chromium-libjpeg-r0.patch
0f8345102f33f16abea3731d76767cb04b06d8422fa8e4c9f7bcc2c18dc8ede5332559c5dd0db25be740939abfd8045adc8de38ec5973367ffe0624e8d9f8b5f  chromium-libwebp-shim-r0.patch
589a7acf149d44db081da2dd24a7769f2b9572a8cc64d2aad78577a64768d3b6fb2bfa02292b5260acd2c4a28c3ae9b82847ff901ce8a21baeca0b46dcda0ca9  media-base.patch
05c1af43038f76014f5f8b605085310414242f2bfad0e3258ddb29a08e7f4307de31b2d551b0a291986cc7d5a01cf3a003ac864216877195bb4310fd33193f0f  musl-crashpad.patch
662eff1417530eed19142c154c40c0a3ffa56e5e2cf30d07683cbbd7cb34860e394e57de31e3552653515ffd654efb762621e2712304fbb8edb0ecdd932d8154  chromium-gcc.patch"
