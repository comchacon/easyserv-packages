#!/bin/bash
# PHP (CLI, FPM, CGI, phpdbg) with statically linked third-party libraries.
# System libraries used from macOS: libxml2, libcurl, sqlite3, zlib, bzip2, libiconv, libedit.

build_php() {
    local source="$1" # sources.lock entry, e.g. php-8.5
    local version major prefix src destdir root
    version="$(source_field "${source}" 2)"
    major="${version%.*}"
    prefix="${INSTALL_ROOT}/php/${major}/${version}"

    for dep in openssl oniguruma libsodium icu4c libzip libpng jpeg-turbo freetype webp; do
        build_dep "${dep}"
    done

    log "Building PHP ${version} (${ARCH})"
    rm -f "${LOGS}/php-${major}.log"
    src="$(unpack "${source}")"
    destdir="${STAGE}/php-${version}"
    rm -rf "${destdir}"

    (
        cd "${src}"
        # Static .pc files list their private dependencies only with --static.
        export PKG_CONFIG="${TOOLS}/pkgconf --static"
        export LIBS="-lc++"

        run_logged "php-${major}" ./configure \
            --host="${HOST_TRIPLE}" \
            --prefix="${prefix}" \
            --with-config-file-path="${ETC_ROOT}/php/${major}" \
            --with-config-file-scan-dir="${ETC_ROOT}/php/${major}/conf.d" \
            --enable-fpm \
            --enable-phpdbg \
            --with-openssl \
            --with-zlib \
            --with-bz2="${SDKROOT}/usr" \
            --with-curl \
            --with-iconv="${SDKROOT}/usr" \
            --with-libedit \
            --enable-mbstring \
            --enable-intl=shared \
            --with-zip \
            --with-sodium \
            --enable-gd --with-jpeg --with-webp --with-freetype \
            --enable-bcmath \
            --enable-calendar \
            --enable-exif \
            --enable-ftp \
            --enable-pcntl \
            --enable-shmop \
            --enable-soap \
            --enable-sockets \
            --enable-sysvmsg --enable-sysvsem --enable-sysvshm \
            --with-mysqli=mysqlnd \
            --with-pdo-mysql=mysqlnd \
            --with-pdo-sqlite \
            --with-sqlite3 \
            --with-pdo-pgsql=no \
            --without-pear
        run_logged "php-${major}" make -j"${JOBS}"
        run_logged "php-${major}" make install INSTALL_ROOT="${destdir}"
    )

    root="${destdir}${prefix}"
    rm -rf "${root}/php/man" "${root}/var"

    # Strip local symbols (the linker signature becomes invalid, so re-sign ad hoc).
    local binary
    for binary in "${root}/bin/php" "${root}/bin/php-cgi" "${root}/bin/phpdbg" "${root}/sbin/php-fpm" \
        "${root}"/lib/php/extensions/*/*.so; do
        [[ -f "${binary}" ]] || continue
        strip -x "${binary}"
        codesign --force --sign - "${binary}" 2>/dev/null
    done
    local extension_dir
    extension_dir="$(cd "${root}"/lib/php/extensions/no-debug-non-zts-* && pwd)"

    log "Smoke test"
    local php=("${root}/bin/php" -n -d "extension_dir=${extension_dir}" -d extension=intl)
    "${php[@]}" -v | head -1
    local modules
    modules="$("${php[@]}" -m | grep -v '^\[' | grep -v '^$' | sort -f | /usr/bin/python3 -c 'import json,sys; print(json.dumps([l.strip() for l in sys.stdin]))')"
    "${php[@]}" -r 'exit(extension_loaded("intl") && extension_loaded("gd") && extension_loaded("mbstring") ? 0 : 1);'

    package_artifact php "${major}" "${version}" "${root}" "{
        \"displayName\": \"PHP\",
        \"category\": \"language\",
        \"service\": \"php\",
        \"links\": {\"bin\": [\"bin/php\", \"bin/php-cgi\", \"bin/php-config\", \"bin/phpdbg\", \"bin/phpize\"]},
        \"shims\": [\"php\", \"php-cgi\", \"php-config\", \"phpdbg\", \"phpize\"],
        \"sharedExtensions\": [\"intl\"],
        \"extensions\": ${modules}
    }"
}
