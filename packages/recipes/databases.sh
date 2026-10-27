#!/bin/bash
# Database servers: PostgreSQL, MariaDB, MySQL.

build_postgresql() {
    local source="$1" version major src
    version="$(source_field "${source}" 2)"
    major="${version%%.*}"
    build_dep openssl
    build_dep icu4c
    log "Building PostgreSQL ${version} (${ARCH})"
    rm -f "${LOGS}/${source}.log"
    stage_prefix postgresql "${major}" "${version}"
    src="$(unpack "${source}")"
    # libpq refuses to link anything that can call exit(). Statically linked OpenSSL only brings in
    # atexit (cleanup handler registration) and pthread_exit (its own helper threads); allow exactly those.
    sed -i '' 's/grep -v -e __cxa_atexit -e __tsan_func_exit | grep exit/grep -v -e __cxa_atexit -e __tsan_func_exit -e "_atexit$$" -e "_pthread_exit$$" | grep exit/' \
        "${src}/src/interfaces/libpq/Makefile"
    (
        cd "${src}"
        export PKG_CONFIG="${TOOLS}/pkgconf --static"
        export LIBS="-lc++"
        run_logged "${source}" ./configure --host="${HOST_TRIPLE}" --prefix="${PREFIX}" \
            --with-openssl --with-icu --with-libedit-preferred --with-uuid=e2fs \
            --without-gssapi --without-ldap --disable-nls --with-system-tzdata=/usr/share/zoneinfo
        run_logged "${source}" make -j"${JOBS}" world-bin
        run_logged "${source}" make install-world-bin DESTDIR="${DESTDIR_STAGE}"
    )
    "${ROOT}/bin/postgres" --version
    # psql links libpq at its final install location; point dyld at the staged copy for the test.
    DYLD_LIBRARY_PATH="${ROOT}/lib" "${ROOT}/bin/psql" --version
    package_artifact postgresql "${major}" "${version}" "${ROOT}" '{
        "displayName": "PostgreSQL", "category": "database", "service": "postgresql",
        "links": {"bin": ["bin/psql", "bin/pg_dump", "bin/pg_dumpall", "bin/pg_restore", "bin/createdb",
                          "bin/dropdb", "bin/createuser", "bin/dropuser", "bin/pg_isready"]}
    }'
}

build_mariadb() {
    local source="$1" version major src
    version="$(source_field "${source}" 2)"
    major="${version%.*}"
    build_dep openssl
    build_dep pcre2
    build_tool_bison
    log "Building MariaDB ${version} (${ARCH})"
    rm -f "${LOGS}/${source}.log"
    stage_prefix mariadb "${major}" "${version}"
    src="$(unpack "${source}")"
    run_logged "${source}" cmake -S "${src}" -B "${src}/_build" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
        -DCMAKE_OSX_ARCHITECTURES="${ARCH}" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${MIN_MACOS}" \
        -DCMAKE_OSX_SYSROOT="${SDKROOT}" \
        -DCMAKE_PREFIX_PATH="${DEPS}" \
        -DCMAKE_IGNORE_PREFIX_PATH="/opt/homebrew;/usr/local;/Applications/ServBay" \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DBISON_EXECUTABLE="${TOOLS}/bison" \
        -DINSTALL_MYSQLTESTDIR= -DINSTALL_SQLBENCHDIR= -DINSTALL_DOCDIR=share/doc -DINSTALL_MANDIR=share/man \
        -DMYSQL_DATADIR=/Applications/EasyServ/db/mariadb/"${major}" \
        -DMYSQL_UNIX_ADDR=/Applications/EasyServ/tmp/mariadb-"${major}".sock \
        -DDEFAULT_SYSCONFDIR=/Applications/EasyServ/etc/mariadb/"${major}" \
        -DWITH_SSL="${DEPS}" -DWITH_PCRE=system -DWITH_ZLIB=system -DWITH_LIBFMT=bundled \
        -DWITH_UNIT_TESTS=OFF -DWITH_EMBEDDED_SERVER=OFF -DWITH_WSREP=OFF -DWITH_MARIABACKUP=ON \
        -DPLUGIN_ROCKSDB=NO -DPLUGIN_MROONGA=NO -DPLUGIN_SPIDER=NO -DPLUGIN_OQGRAPH=NO \
        -DPLUGIN_CONNECT=NO -DPLUGIN_COLUMNSTORE=NO -DPLUGIN_S3=NO -DPLUGIN_PERFSCHEMA=YES \
        -DPLUGIN_AUTH_GSSAPI=NO -DPLUGIN_AUTH_GSSAPI_CLIENT=OFF -DPLUGIN_PROVIDER_LZ4=NO \
        -DPLUGIN_PROVIDER_LZO=NO -DPLUGIN_PROVIDER_LZMA=NO -DPLUGIN_PROVIDER_SNAPPY=NO -DPLUGIN_PROVIDER_BZIP2=NO \
        -DWITH_INNODB_LZ4=OFF -DWITH_INNODB_LZO=OFF -DWITH_INNODB_LZMA=OFF -DWITH_INNODB_SNAPPY=OFF \
        -DWITH_INNODB_BZIP2=OFF -DGRN_WITH_MESSAGE_PACK=no
    run_logged "${source}" cmake --build "${src}/_build" -j "${JOBS}"
    run_logged "${source}" env DESTDIR="${DESTDIR_STAGE}" cmake --install "${src}/_build"
    rm -rf "${ROOT}/share/man" "${ROOT}/share/doc" "${ROOT}/mysql-test" "${ROOT}/sql-bench"
    "${ROOT}/bin/mariadbd" --version
    package_artifact mariadb "${major}" "${version}" "${ROOT}" '{
        "displayName": "MariaDB", "category": "database", "service": "mariadb",
        "links": {"bin": ["bin/mariadb", "bin/mariadb-dump", "bin/mariadb-admin", "bin/mariadb-import"]}
    }'
}

build_mysql() {
    local source="$1" version major src
    version="$(source_field "${source}" 2)"
    major="${version%.*}"
    build_dep openssl-shared
    build_tool_bison
    if [[ "${REPACKAGE:-}" == "1" && -d "${STAGE}/mysql-${version}" ]]; then
        # Reuse the staged install (skips the ~30 min compile), only redo post-processing + packaging.
        PREFIX="${INSTALL_ROOT}/mysql/${major}/${version}"
        DESTDIR_STAGE="${STAGE}/mysql-${version}"
        ROOT="${DESTDIR_STAGE}${PREFIX}"
        finish_mysql "${major}" "${version}"
        return
    fi
    log "Building MySQL ${version} (${ARCH})"
    rm -f "${LOGS}/${source}.log"
    stage_prefix mysql "${major}" "${version}"
    src="$(unpack "${source}")"
    # MySQL bundles its own ICU/zlib/zstd; keep our static deps (ICU 78 headers!) out of its include
    # and library search paths.
    local mysql_env=(env -u CPPFLAGS LDFLAGS="-arch ${ARCH}")
    run_logged "${source}" "${mysql_env[@]}" cmake -S "${src}" -B "${src}/_build" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
        -DCMAKE_OSX_ARCHITECTURES="${ARCH}" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${MIN_MACOS}" \
        -DCMAKE_OSX_SYSROOT="${SDKROOT}" \
        -DCMAKE_IGNORE_PREFIX_PATH="/opt/homebrew;/usr/local;/Applications/ServBay" \
        -DBISON_EXECUTABLE="${TOOLS}/bison" \
        -DINSTALL_MYSQLTESTDIR= -DINSTALL_DOCDIR=share/doc -DINSTALL_MANDIR=share/man \
        -DMYSQL_DATADIR=/Applications/EasyServ/db/mysql/"${major}" \
        -DMYSQL_UNIX_ADDR=/Applications/EasyServ/tmp/mysql-"${major}".sock \
        -DSYSCONFDIR=/Applications/EasyServ/etc/mysql/"${major}" \
        -DWITH_SSL="${OPENSSL_SHARED}" -DWITH_ZLIB=bundled -DWITH_ZSTD=bundled -DWITH_LZ4=bundled \
        -DWITH_ICU=bundled -DWITH_PROTOBUF=bundled -DWITH_EDITLINE=bundled -DWITH_FIDO=none \
        -DWITH_UNIT_TESTS=OFF -DWITH_ROUTER=OFF -DWITH_NDB=OFF -DWITH_NDBCLUSTER=OFF \
        -DWITH_AUTHENTICATION_LDAP=OFF -DWITH_AUTHENTICATION_KERBEROS=OFF -DWITH_AUTHENTICATION_FIDO=OFF \
        -DWITH_AUTHENTICATION_CLIENT_PLUGINS=OFF -DWITH_MYSQLX=ON -DENABLED_LOCAL_INFILE=ON
    run_logged "${source}" "${mysql_env[@]}" cmake --build "${src}/_build" -j "${JOBS}"
    run_logged "${source}" env DESTDIR="${DESTDIR_STAGE}" cmake --install "${src}/_build"
    rm -rf "${ROOT}/share/man" "${ROOT}/share/doc" "${ROOT}/mysql-test"
    finish_mysql "${major}" "${version}"
}

finish_mysql() {
    local major="$1" version="$2"
    # MySQL copies the shared OpenSSL into lib/ and lib/plugin/ but keeps build-time references.
    relink_bundled "${ROOT}" "${OPENSSL_SHARED}/lib"
    # Test and developer tools are not needed at runtime.
    rm -f "${ROOT}"/bin/mysql_client_test "${ROOT}"/bin/mysqltest* "${ROOT}"/bin/mysqlxtest \
        "${ROOT}"/bin/mysql_keyring_encryption_test "${ROOT}"/bin/mysql_test_event_tracking
    rm -f "${ROOT}"/lib/plugin/*test*
    "${ROOT}/bin/mysqld" --version
    package_artifact mysql "${major}" "${version}" "${ROOT}" '{
        "displayName": "MySQL", "category": "database", "service": "mysql",
        "links": {"bin": ["bin/mysql", "bin/mysqldump", "bin/mysqladmin", "bin/mysqlimport"]}
    }'
}
