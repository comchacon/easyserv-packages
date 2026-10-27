#!/bin/bash
# NGINX with static OpenSSL 3 and PCRE2.

build_nginx() {
    local version major prefix src destdir root
    version="$(source_field nginx 2)"
    major="${version%.*}"
    prefix="${INSTALL_ROOT}/nginx/${major}/${version}"

    build_dep openssl
    build_dep pcre2

    log "Building nginx ${version} (${ARCH})"
    rm -f "${LOGS}/nginx.log"
    src="$(unpack nginx)"
    destdir="${STAGE}/nginx-${version}"
    rm -rf "${destdir}"

    (
        cd "${src}"
        run_logged nginx ./configure \
            --prefix="${prefix}" \
            --sbin-path="${prefix}/sbin/nginx" \
            --conf-path="${ETC_ROOT}/nginx/nginx.conf" \
            --error-log-path=/Applications/EasyServ/logs/nginx/error.log \
            --http-log-path=/Applications/EasyServ/logs/nginx/access.log \
            --pid-path=/Applications/EasyServ/tmp/nginx.pid \
            --lock-path=/Applications/EasyServ/tmp/nginx.lock \
            --http-client-body-temp-path=/Applications/EasyServ/tmp/nginx/client_body \
            --http-proxy-temp-path=/Applications/EasyServ/tmp/nginx/proxy \
            --http-fastcgi-temp-path=/Applications/EasyServ/tmp/nginx/fastcgi \
            --http-uwsgi-temp-path=/Applications/EasyServ/tmp/nginx/uwsgi \
            --http-scgi-temp-path=/Applications/EasyServ/tmp/nginx/scgi \
            --with-cc="$(xcrun -f clang)" \
            --with-cc-opt="${CFLAGS} -I${DEPS}/include" \
            --with-ld-opt="${LDFLAGS}" \
            --with-pcre --with-pcre-jit \
            --with-threads \
            --with-http_ssl_module \
            --with-http_v2_module \
            --with-http_v3_module \
            --with-http_realip_module \
            --with-http_addition_module \
            --with-http_sub_module \
            --with-http_dav_module \
            --with-http_gunzip_module \
            --with-http_gzip_static_module \
            --with-http_auth_request_module \
            --with-http_secure_link_module \
            --with-http_slice_module \
            --with-http_stub_status_module \
            --with-stream \
            --with-stream_ssl_module \
            --with-stream_ssl_preread_module \
            --with-stream_realip_module
        run_logged nginx make -j"${JOBS}"
        run_logged nginx make install DESTDIR="${destdir}"
    )

    root="${destdir}${prefix}"
    # Keep the upstream default configuration files as reference inside the package.
    mkdir -p "${root}/share/conf"
    cp -R "${destdir}${ETC_ROOT}/nginx/." "${root}/share/conf/"

    log "Smoke test"
    "${root}/sbin/nginx" -V 2>&1 | head -3

    package_artifact nginx "${major}" "${version}" "${root}" '{
        "displayName": "NGINX",
        "category": "webserver",
        "service": "nginx",
        "links": {"sbin": ["sbin/nginx"]}
    }'
}
