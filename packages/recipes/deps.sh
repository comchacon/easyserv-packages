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

# --- PHP extension libraries (Phase 5d), all static so the extension modules stay self-contained ---

# libpq for pgsql/pdo_pgsql, from the PostgreSQL source. libpgcommon/libpgport are merged into libpq.a
# (the _shlib variants – libpq uses their symbol names) because PHP only links -lpq.
dep_libpq() {
    build_dep openssl
    local src
    src="$(unpack postgresql-18)"
    sed -i '' 's/grep -v -e __cxa_atexit -e __tsan_func_exit | grep exit/grep -v -e __cxa_atexit -e __tsan_func_exit -e "_atexit$$" -e "_pthread_exit$$" | grep exit/' \
        "${src}/src/interfaces/libpq/Makefile"
    (
        cd "${src}"
        export PKG_CONFIG="${TOOLS}/pkgconf --static"
        run_logged dep-libpq ./configure --host="${HOST_TRIPLE}" --prefix="${DEPS}" --with-openssl --without-icu \
            --without-readline --without-gssapi --without-ldap --disable-nls
        for dir in src/include src/common src/port src/interfaces/libpq src/bin/pg_config; do
            run_logged dep-libpq make -C "${dir}" -j"${JOBS}"
            run_logged dep-libpq make -C "${dir}" install
        done
    )
    rm -f "${DEPS}"/lib/libpq*.dylib
    libtool -static -o "${DEPS}/lib/libpq-merged.a" "${DEPS}/lib/libpq.a" "${DEPS}/lib/libpgcommon_shlib.a" "${DEPS}/lib/libpgport_shlib.a"
    mv "${DEPS}/lib/libpq-merged.a" "${DEPS}/lib/libpq.a"
}

dep_gmp() {
    local src
    src="$(unpack gmp)"
    (
        cd "${src}"
        run_logged dep-gmp ./configure --host="${HOST_TRIPLE}" --prefix="${DEPS}" --disable-shared --enable-static --with-pic
        run_logged dep-gmp make -j"${JOBS}"
        run_logged dep-gmp make install
    )
}

# libintl only (gettext-runtime), for the gettext extension. Own prefix: libintl.h redefines setlocale(), which
# must not leak into the rest of PHP through the shared include directory.
dep_gettext() {
    local src
    src="$(unpack gettext)"
    (
        cd "${src}/gettext-runtime"
        # Without CoreFoundation lookups, so libintl.a only needs libiconv (PHP sets locales via setlocale anyway).
        export gt_cv_func_CFPreferencesCopyAppValue=no gt_cv_func_CFLocaleCopyCurrent=no \
            gt_cv_func_CFLocaleCopyPreferredLanguages=no
        run_logged dep-gettext ./configure --host="${HOST_TRIPLE}" --prefix="${DEPS}/gettext" --disable-shared --enable-static \
            --with-included-gettext --disable-java --disable-csharp --disable-libasprintf --without-emacs \
            --with-libiconv-prefix="${SDKROOT}/usr" --disable-c++
        run_logged dep-gettext make -C intl -j"${JOBS}"
        run_logged dep-gettext make -C intl install
    )
}

dep_tidy_html5() {
    local src
    src="$(unpack tidy-html5)"
    run_logged dep-tidy cmake -S "${src}" -B "${src}/_build" -DCMAKE_INSTALL_PREFIX="${DEPS}" -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES="${ARCH}" -DCMAKE_OSX_DEPLOYMENT_TARGET="${MIN_MACOS}" -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DBUILD_SHARED_LIB=OFF -DSUPPORT_LOCALIZATIONS=OFF -DTIDY_COMPAT_HEADERS=ON
    run_logged dep-tidy cmake --build "${src}/_build" -j "${JOBS}"
    run_logged dep-tidy cmake --install "${src}/_build"
    # The static library is called libtidy_static.a; PHP links -ltidy.
    [[ -f "${DEPS}/lib/libtidy.a" ]] || ln -sf libtidy_static.a "${DEPS}/lib/libtidy.a"
    rm -f "${DEPS}"/lib/libtidy*.dylib
}

dep_libmemcached() {
    local src
    src="$(unpack libmemcached)"
    run_logged dep-libmemcached cmake -S "${src}" -B "${src}/_build" -DCMAKE_INSTALL_PREFIX="${DEPS}" -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES="${ARCH}" -DCMAKE_OSX_DEPLOYMENT_TARGET="${MIN_MACOS}" -DBUILD_SHARED_LIBS=OFF \
        -DBUILD_TESTING=OFF -DENABLE_SASL=OFF -DENABLE_DTRACE=OFF -DENABLE_OPENSSL_CRYPTO=OFF -DBUILD_DOCS=OFF \
        -DENABLE_MEMASLAP=OFF
    run_logged dep-libmemcached cmake --build "${src}/_build" -j "${JOBS}"
    run_logged dep-libmemcached cmake --install "${src}/_build"
    rm -f "${DEPS}"/lib/libmemcached*.dylib "${DEPS}"/lib/libhashkit*.dylib
}
