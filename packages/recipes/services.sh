#!/bin/bash
# Small daemons built from source: dnsmasq, memcached, redis.

# stage_prefix <name> <major> <version> -> sets PREFIX, DESTDIR_STAGE, ROOT
stage_prefix() {
    PREFIX="${INSTALL_ROOT}/$1/$2/$3"
    DESTDIR_STAGE="${STAGE}/$1-$3"
    ROOT="${DESTDIR_STAGE}${PREFIX}"
    rm -rf "${DESTDIR_STAGE}"
}

build_dnsmasq() {
    local version major="2" src
    version="$(source_field dnsmasq 2)"
    log "Building dnsmasq ${version} (${ARCH})"
    rm -f "${LOGS}/dnsmasq.log"
    stage_prefix dnsmasq "${major}" "${version}"
    src="$(unpack dnsmasq)"
    (
        cd "${src}"
        run_logged dnsmasq make -j"${JOBS}" PREFIX="${PREFIX}" CC="${CC}" CFLAGS="${CFLAGS}" LDFLAGS="${LDFLAGS}" COPTS=""
    )
    mkdir -p "${ROOT}/sbin" "${ROOT}/share"
    install -m 0755 "${src}/src/dnsmasq" "${ROOT}/sbin/dnsmasq"
    cp "${src}/COPYING" "${ROOT}/share/COPYING"
    "${ROOT}/sbin/dnsmasq" --version | head -1
    package_artifact dnsmasq "${major}" "${version}" "${ROOT}" '{
        "displayName": "dnsmasq", "category": "dns", "service": "dnsmasq",
        "links": {"sbin": ["sbin/dnsmasq"]}
    }'
}

build_memcached() {
    local version major="1.6" src
    version="$(source_field memcached 2)"
    build_dep libevent
    log "Building memcached ${version} (${ARCH})"
    rm -f "${LOGS}/memcached.log"
    stage_prefix memcached "${major}" "${version}"
    src="$(unpack memcached)"
    (
        cd "${src}"
        run_logged memcached ./configure --host="${HOST_TRIPLE}" --prefix="${PREFIX}" --with-libevent="${DEPS}" \
            --disable-docs --disable-coverage \
            ac_cv_func_sandbox_init=no # sandbox_init profiles were removed from the macOS 27 SDK
        run_logged memcached make -j"${JOBS}"
        run_logged memcached make install DESTDIR="${DESTDIR_STAGE}"
    )
    rm -rf "${ROOT}/share/man"
    "${ROOT}/bin/memcached" --version
    package_artifact memcached "${major}" "${version}" "${ROOT}" '{
        "displayName": "Memcached", "category": "nosql", "service": "memcached",
        "links": {"bin": ["bin/memcached"]}
    }'
}

build_redis() {
    local version major="8" src
    version="$(source_field redis 2)"
    build_dep openssl
    log "Building redis ${version} (${ARCH})"
    rm -f "${LOGS}/redis.log"
    stage_prefix redis "${major}" "${version}"
    src="$(unpack redis)"
    (
        cd "${src}"
        # Redis builds its bundled deps (hiredis, lua, …) with these flags; OpenSSL is linked statically.
        # Only the server/tools in src/ (the top-level target also links test modules with plain ld).
        # Minimum macOS comes from MACOSX_DEPLOYMENT_TARGET; LDFLAGS would reach ld directly.
        run_logged redis make -C src -j"${JOBS}" BUILD_TLS=yes OPENSSL_PREFIX="${DEPS}" MALLOC=libc \
            CC="${CC}" CXX="${CXX}" CFLAGS="${CFLAGS}" LDFLAGS="" V=1
        run_logged redis make -C src install PREFIX="${ROOT}" BUILD_TLS=yes OPENSSL_PREFIX="${DEPS}" MALLOC=libc \
            CC="${CC}" CXX="${CXX}" CFLAGS="${CFLAGS}" LDFLAGS=""
    )
    "${ROOT}/bin/redis-server" --version
    package_artifact redis "${major}" "${version}" "${ROOT}" '{
        "displayName": "Redis", "category": "nosql", "service": "redis",
        "links": {"bin": ["bin/redis-server", "bin/redis-cli", "bin/redis-benchmark"]}
    }'
}
