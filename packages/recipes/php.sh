#!/bin/bash
# PHP (CLI, FPM, CGI, phpdbg) with statically linked third-party libraries.
# System libraries used from macOS: libxml2, libcurl, sqlite3, zlib, bzip2, libiconv, libedit.

build_php() {
    local source="$1" # sources.lock entry, e.g. php-8.5
    local version major prefix src destdir root
    version="$(source_field "${source}" 2)"
    major="${version%.*}"
    prefix="${INSTALL_ROOT}/php/${major}/${version}"

    for dep in openssl oniguruma libsodium icu4c libzip libpng jpeg-turbo freetype webp libpq gmp gettext tidy-html5 \
        libyaml libmemcached; do
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
        # libintl.h would redirect setlocale()/newlocale() to libintl's versions for all of PHP (string.c includes it).
        export CPPFLAGS="${CPPFLAGS} -DGNULIB_defined_setlocale=1 -DGNULIB_defined_newlocale=1"

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
            --with-pgsql=shared,"${DEPS}" \
            --with-pdo-pgsql=shared,"${DEPS}" \
            --with-gmp=shared,"${DEPS}" \
            --with-gettext=shared,"${DEPS}/gettext" \
            --with-tidy=shared,"${DEPS}" \
            --with-xsl=shared \
            --without-pear
        run_logged "php-${major}" make -j"${JOBS}"
        run_logged "php-${major}" make install INSTALL_ROOT="${destdir}"
    )

    root="${destdir}${prefix}"
    rm -rf "${root}/php/man" "${root}/var"
    build_php_pecl "${major}" "${prefix}" "${root}"

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
    local base=("${root}/bin/php" -n -d "extension_dir=${extension_dir}")
    "${base[@]}" -v | head -1
    local modules
    modules="$("${base[@]}" -m | grep -v '^\[' | grep -v '^$' | sort -f | /usr/bin/python3 -c 'import json,sys; print(json.dumps([l.strip() for l in sys.stdin]))')"
    # Every module must load (in dependency order, as conf.d/00-easyserv.ini does).
    local load=() name loaded
    local builtin
    builtin="$("${base[@]}" -m)"
    local order=()
    for name in ${PHP_EXTENSION_LOAD_ORDER}; do
        # PHP 8.5 always compiles OPcache in.
        if [[ "${name}" == opcache ]] && grep -qx "Zend OPcache" <<<"${builtin}"; then continue; fi
        order+=("${name}")
    done
    for name in "${order[@]}"; do
        [[ -f "${extension_dir}/${name}.so" ]] || { echo "Missing extension ${name}" >&2; exit 1; }
        if [[ " ${PHP_ZEND_EXTENSIONS} " == *" ${name} "* ]]; then load+=(-d "zend_extension=${name}"); else load+=(-d "extension=${name}"); fi
    done
    loaded="$("${base[@]}" "${load[@]}" -m 2>&1)"
    for name in "${order[@]}"; do
        local module_name="${name}"
        [[ "${name}" == opcache ]] && module_name="Zend OPcache"
        [[ "${name}" == xdebug ]] && module_name="Xdebug"
        grep -qx "${module_name}" <<<"${loaded}" || { echo "Extension ${name} does not load:" >&2; echo "${loaded}" | head -20 >&2; exit 1; }
    done
    "${base[@]}" "${load[@]}" -r 'exit(extension_loaded("intl") && extension_loaded("pdo_pgsql") && extension_loaded("redis") ? 0 : 1);'

    package_artifact php "${major}" "${version}" "${root}" "{
        \"displayName\": \"PHP\",
        \"category\": \"language\",
        \"service\": \"php\",
        \"links\": {\"bin\": [\"bin/php\", \"bin/php-cgi\", \"bin/php-config\", \"bin/phpdbg\", \"bin/phpize\"]},
        \"shims\": [\"php\", \"php-cgi\", \"php-config\", \"phpdbg\", \"phpize\"],
        \"revision\": 2,
        \"sharedExtensions\": $(php_json_list ${PHP_DEFAULT_EXTENSIONS}),
        \"optionalExtensions\": $(php_json_list ${PHP_OPTIONAL_EXTENSIONS}),
        \"extensions\": ${modules}
    }"
}

# Modules shipped as .so: enabled by default / available but off (Xdebug and PCOV slow PHP down).
PHP_DEFAULT_EXTENSIONS="intl pgsql pdo_pgsql gmp xsl apcu igbinary msgpack redis yaml"
PHP_OPTIONAL_EXTENSIONS="gettext tidy mongodb memcached pcov xdebug"
PHP_ZEND_EXTENSIONS="opcache xdebug"
# Dependencies first (redis needs igbinary + msgpack, memcached needs igbinary).
PHP_EXTENSION_LOAD_ORDER="opcache intl pgsql pdo_pgsql gmp xsl gettext tidy apcu igbinary msgpack redis yaml mongodb memcached pcov xdebug"

php_json_list() {
    /usr/bin/python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$@"
}

# build_php_pecl <major> <prefix> <staged root> – PECL extensions built with phpize against the staged PHP.
# php-config/phpize carry the final install prefix; copies pointing at the staged root are used for the build.
build_php_pecl() {
    local major="$1" prefix="$2" root="$3" tools="${SRC}/php-${1}-tools"
    rm -rf "${tools}"
    mkdir -p "${tools}"
    sed "s#${prefix}#${root}#g" "${root}/bin/php-config" >"${tools}/php-config"
    sed "s#${prefix}#${root}#g" "${root}/bin/phpize" >"${tools}/phpize"
    chmod +x "${tools}/php-config" "${tools}/phpize"

    pecl_build "${major}" "${tools}" igbinary
    pecl_build "${major}" "${tools}" msgpack
    pecl_build "${major}" "${tools}" apcu
    pecl_build "${major}" "${tools}" xdebug
    pecl_build "${major}" "${tools}" pcov --enable-pcov
    pecl_build "${major}" "${tools}" yaml --with-yaml="${DEPS}"
    pecl_build "${major}" "${tools}" redis --enable-redis-igbinary --enable-redis-msgpack --enable-redis-lzf
    LIBS="-lc++" pecl_build "${major}" "${tools}" memcached --with-libmemcached-dir="${DEPS}" --disable-memcached-sasl \
        --enable-memcached-igbinary --with-zlib-dir="${SDKROOT}/usr"
    pecl_build "${major}" "${tools}" mongodb --with-mongodb-ssl=openssl --with-openssl-dir="${DEPS}" \
        --with-mongodb-system-libs=no --with-mongodb-sasl=no --with-mongodb-icu=no --with-mongodb-snappy=no \
        --with-mongodb-zstd=no --with-mongodb-client-side-encryption=no
}

pecl_build() {
    local major="$1" tools="$2" name="$3" src
    shift 3
    log "PHP ${major}: ${name} $(source_field "pecl-${name}" 2)"
    src="$(unpack "pecl-${name}")"
    (
        cd "${src}"
        export PKG_CONFIG="${TOOLS}/pkgconf --static"
        export PHP_AUTOCONF="${TOOLS}/autoconf" PHP_AUTOHEADER="${TOOLS}/autoheader"
        run_logged "php-${major}-${name}" "${tools}/phpize"
        run_logged "php-${major}-${name}" ./configure --host="${HOST_TRIPLE}" --with-php-config="${tools}/php-config" "$@"
        run_logged "php-${major}-${name}" make -j"${JOBS}"
        run_logged "php-${major}-${name}" make install
    )
}
