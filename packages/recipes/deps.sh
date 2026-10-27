#!/bin/bash
# Static third-party libraries, installed into ${DEPS} (per architecture).

build_dep() {
    local name="$1"
    if dep_built "${name}"; then
        return 0
    fi
    log "Building dependency ${name} $(dep_version "${name}") (${ARCH})"
    rm -f "${LOGS}/dep-${name}.log"
    "dep_${name//-/_}"
    mark_dep_built "${name}"
}

dep_openssl() {
    local src
    src="$(unpack openssl)"
    local target="darwin64-${ARCH}-cc"
    (
        cd "${src}"
        # The OpenSSL Configure script adds -arch itself.
        run_logged dep-openssl env -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS CC="$(xcrun -f clang)" \
            ./Configure "${target}" no-shared no-tests no-docs \
            --prefix="${DEPS}" --libdir=lib --openssldir="/Applications/EasyServ/etc/openssl" \
            "-mmacosx-version-min=${MIN_MACOS}"
        run_logged dep-openssl make -j"${JOBS}"
        run_logged dep-openssl make install_sw
    )
}

dep_pcre2() {
    local src
    src="$(unpack pcre2)"
    (
        cd "${src}"
        run_logged dep-pcre2 ./configure --host="${HOST_TRIPLE}" --prefix="${DEPS}" --disable-shared --enable-static \
            --enable-jit --enable-pcre2-16 --enable-pcre2-32
        run_logged dep-pcre2 make -j"${JOBS}"
        run_logged dep-pcre2 make install
    )
}

dep_oniguruma() {
    local src
    src="$(unpack oniguruma)"
    (
        cd "${src}"
        run_logged dep-oniguruma ./configure --host="${HOST_TRIPLE}" --prefix="${DEPS}" --disable-shared --enable-static
        run_logged dep-oniguruma make -j"${JOBS}"
        run_logged dep-oniguruma make install
    )
}

dep_libsodium() {
    local src
    src="$(unpack libsodium)"
    (
        cd "${src}"
        run_logged dep-libsodium ./configure --host="${HOST_TRIPLE}" --prefix="${DEPS}" --disable-shared --enable-static
        run_logged dep-libsodium make -j"${JOBS}"
        run_logged dep-libsodium make install
    )
}

dep_icu4c() {
    local src
    src="$(unpack icu4c)"
    (
        cd "${src}/source"
        run_logged dep-icu4c ./configure --host="${HOST_TRIPLE}" --prefix="${DEPS}" --disable-shared --enable-static \
            --with-data-packaging=static --disable-samples --disable-tests --disable-extras
        run_logged dep-icu4c make -j"${JOBS}"
        run_logged dep-icu4c make install
    )
}

cmake_static() { # <logname> <source> [extra cmake args...]
    local logname="$1" src="$2"
    shift 2
    run_logged "${logname}" cmake -S "${src}" -B "${src}/_build" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${DEPS}" \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DCMAKE_OSX_ARCHITECTURES="${ARCH}" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${MIN_MACOS}" \
        -DCMAKE_OSX_SYSROOT="${SDKROOT}" \
        -DCMAKE_PREFIX_PATH="${DEPS}" \
        -DCMAKE_FIND_FRAMEWORK=NEVER \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DCMAKE_IGNORE_PREFIX_PATH="/opt/homebrew;/usr/local;/Applications/ServBay" \
        -DBUILD_SHARED_LIBS=OFF \
        "$@"
    run_logged "${logname}" cmake --build "${src}/_build" -j "${JOBS}"
    run_logged "${logname}" cmake --install "${src}/_build"
}

dep_libzip() {
    local src
    src="$(unpack libzip)"
    cmake_static dep-libzip "${src}" \
        -DENABLE_COMMONCRYPTO=ON -DENABLE_GNUTLS=OFF -DENABLE_MBEDTLS=OFF -DENABLE_OPENSSL=OFF \
        -DENABLE_BZIP2=ON -DENABLE_LZMA=OFF -DENABLE_ZSTD=OFF \
        -DBUILD_TOOLS=OFF -DBUILD_REGRESS=OFF -DBUILD_OSSFUZZ=OFF -DBUILD_EXAMPLES=OFF -DBUILD_DOC=OFF
}

dep_libpng() {
    local src
    src="$(unpack libpng)"
    (
        cd "${src}"
        run_logged dep-libpng ./configure --host="${HOST_TRIPLE}" --prefix="${DEPS}" --disable-shared --enable-static
        run_logged dep-libpng make -j"${JOBS}"
        run_logged dep-libpng make install
    )
}

dep_jpeg_turbo() {
    local src
    src="$(unpack jpeg-turbo)"
    cmake_static dep-jpeg-turbo "${src}" -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DWITH_TURBOJPEG=OFF \
        -DCMAKE_SYSTEM_PROCESSOR="${ARCH}"
}

dep_freetype() {
    local src
    src="$(unpack freetype)"
    (
        cd "${src}"
        run_logged dep-freetype ./configure --host="${HOST_TRIPLE}" --prefix="${DEPS}" --disable-shared --enable-static \
            --with-png=yes --with-zlib=yes --with-bzip2=no --with-brotli=no --with-harfbuzz=no
        run_logged dep-freetype make -j"${JOBS}"
        run_logged dep-freetype make install
    )
}

dep_webp() {
    local src
    src="$(unpack webp)"
    cmake_static dep-webp "${src}" -DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF \
        -DWEBP_BUILD_GIF2WEBP=OFF -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF -DWEBP_BUILD_WEBPINFO=OFF \
        -DWEBP_BUILD_WEBPMUX=OFF -DWEBP_BUILD_EXTRAS=OFF
}

dep_libevent() {
    local src
    src="$(unpack libevent)"
    (
        cd "${src}"
        run_logged dep-libevent ./configure --host="${HOST_TRIPLE}" --prefix="${DEPS}" --disable-shared --enable-static \
            --disable-openssl --disable-samples --disable-libevent-regress
        run_logged dep-libevent make -j"${JOBS}"
        run_logged dep-libevent make install
    )
}

# Shared OpenSSL in a separate prefix, only for MySQL: its CMake (WITH_SSL=<path>) bundles the
# dylibs into the package and rewrites them to @loader_path itself.
OPENSSL_SHARED="${WORK}/deps-shared/${ARCH}"

dep_openssl_shared() {
    local src
    src="$(unpack openssl)"
    (
        cd "${src}"
        run_logged dep-openssl-shared env -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS CC="$(xcrun -f clang)" \
            ./Configure "darwin64-${ARCH}-cc" shared no-tests no-docs \
            --prefix="${OPENSSL_SHARED}" --libdir=lib --openssldir="/Applications/EasyServ/etc/openssl" \
            "-mmacosx-version-min=${MIN_MACOS}"
        run_logged dep-openssl-shared make -j"${JOBS}"
        run_logged dep-openssl-shared make install_sw
    )
}

dep_libyaml() {
    local src
    src="$(unpack libyaml)"
    (
        cd "${src}"
        run_logged dep-libyaml ./configure --host="${HOST_TRIPLE}" --prefix="${DEPS}" --disable-shared --enable-static
        run_logged dep-libyaml make -j"${JOBS}"
        run_logged dep-libyaml make install
    )
}
