#!/bin/bash
# Programming languages: official vendor builds (Python via python-build-standalone, Go, Temurin
# Java, Bun, Deno) repackaged with pinned checksums, Ruby built from source.

# Go architecture names
go_arch() { [[ "${ARCH}" == "arm64" ]] && echo arm64 || echo amd64; }

build_python() {
    local major="$1" source="python-$1-${ARCH}" version src
    version="$(source_field "${source}" 2)"
    log "Packaging Python ${version} (${ARCH})"
    stage_prefix python "${major}" "${version}"
    src="$(unpack "${source}")"
    mkdir -p "${ROOT}"
    cp -R "${src}/." "${ROOT}/"
    rm -rf "${ROOT}/share/man"
    ln -sf "python${major}" "${ROOT}/bin/python"
    ln -sf "pip${major}" "${ROOT}/bin/pip"
    # The package is root-owned: pip outside a virtual environment would fail halfway (PEP 668).
    cat >"${ROOT}/lib/python${major}/EXTERNALLY-MANAGED" <<'EOF'
[externally-managed]
Error=This Python is managed by EasyServ. Create a virtual environment instead:
 python -m venv .venv && source .venv/bin/activate
EOF
    "${ROOT}/bin/python" --version
    "${ROOT}/bin/python" -c "import ssl, sqlite3, venv; print(ssl.OPENSSL_VERSION)"
    package_artifact python "${major}" "${version}" "${ROOT}" '{
        "displayName": "Python", "category": "language",
        "links": {"bin": ["bin/python", "bin/python3", "bin/pip", "bin/pip3"]},
        "shims": ["python", "python3", "pip", "pip3"]
    }'
}

build_go() {
    local major="$1" source="go-$1-${ARCH}" version src
    version="$(source_field "${source}" 2)"
    log "Packaging Go ${version} (${ARCH})"
    stage_prefix go "${major}" "${version}"
    src="$(unpack "${source}")"
    mkdir -p "${ROOT}"
    cp -R "${src}/." "${ROOT}/"
    rm -rf "${ROOT}/test" "${ROOT}/api"
    "${ROOT}/bin/go" version
    package_artifact go "${major}" "${version}" "${ROOT}" '{
        "displayName": "Go", "category": "language",
        "links": {"bin": ["bin/go", "bin/gofmt"]},
        "shims": ["go", "gofmt"]
    }'
}

build_java() {
    local major="$1" source="java-$1-${ARCH}" version src
    version="$(source_field "${source}" 2)"
    log "Packaging Java (Temurin) ${version} (${ARCH})"
    stage_prefix java "${major}" "${version}"
    src="$(unpack "${source}")"
    mkdir -p "${ROOT}"
    # Flatten the macOS bundle layout (Contents/Home) – java finds its runtime relative to bin/.
    cp -R "${src}/Contents/Home/." "${ROOT}/"
    rm -rf "${ROOT}/man" "${ROOT}/lib/src.zip"
    "${ROOT}/bin/java" -version 2>&1 | sed -n 1p
    package_artifact java "${major}" "${version}" "${ROOT}" '{
        "displayName": "Java (Temurin)", "category": "language",
        "links": {"bin": ["bin/java", "bin/javac", "bin/jar", "bin/jshell", "bin/keytool"]},
        "shims": ["java", "javac", "jar", "jshell", "keytool"]
    }'
}

build_bun() {
    local major="1" source="bun-${ARCH}" version
    version="$(source_field "${source}" 2)"
    log "Packaging Bun ${version} (${ARCH})"
    stage_prefix bun "${major}" "${version}"
    unpack_flat "${source}" "${SRC}/bun"
    mkdir -p "${ROOT}/bin"
    install -m 0755 "${SRC}"/bun/bun-darwin-*/bun "${ROOT}/bin/bun"
    ln -sf bun "${ROOT}/bin/bunx"
    "${ROOT}/bin/bun" --version
    package_artifact bun "${major}" "${version}" "${ROOT}" '{
        "displayName": "Bun", "category": "language",
        "links": {"bin": ["bin/bun", "bin/bunx"]},
        "shims": ["bun", "bunx"]
    }'
}

build_deno() {
    local major="2" source="deno-${ARCH}" version
    version="$(source_field "${source}" 2)"
    log "Packaging Deno ${version} (${ARCH})"
    stage_prefix deno "${major}" "${version}"
    unpack_flat "${source}" "${SRC}/deno"
    mkdir -p "${ROOT}/bin"
    install -m 0755 "${SRC}/deno/deno" "${ROOT}/bin/deno"
    "${ROOT}/bin/deno" --version | sed -n 1p
    package_artifact deno "${major}" "${version}" "${ROOT}" '{
        "displayName": "Deno", "category": "language",
        "links": {"bin": ["bin/deno"]},
        "shims": ["deno"]
    }'
}

build_ruby() {
    local major="$1" source="ruby-$1" version src
    version="$(source_field "${source}" 2)"
    build_dep openssl
    build_dep libyaml
    log "Building Ruby ${version} (${ARCH})"
    rm -f "${LOGS}/${source}.log"
    stage_prefix ruby "${major}" "${version}"
    src="$(unpack "${source}")"
    (
        cd "${src}"
        # --enable-load-relative: the interpreter finds its library relative to bin/ruby.
        run_logged "${source}" ./configure --host="${HOST_TRIPLE}" --prefix="${PREFIX}" \
            --enable-load-relative --disable-install-doc --disable-install-rdoc --without-gmp \
            --with-openssl-dir="${DEPS}" --with-libyaml-dir="${DEPS}" \
            --with-opt-dir="${DEPS}"
        run_logged "${source}" make -j"${JOBS}"
        run_logged "${source}" make install DESTDIR="${DESTDIR_STAGE}"
    )
    # Ruby 4.0 with load-relative drops the prefix and installs at the DESTDIR root.
    if [[ ! -x "${ROOT}/bin/ruby" && -x "${DESTDIR_STAGE}/bin/ruby" ]]; then
        mkdir -p "${ROOT}"
        local entry
        for entry in "${DESTDIR_STAGE}"/*; do
            [[ "${entry}" == "${DESTDIR_STAGE}/Applications" ]] || mv "${entry}" "${ROOT}/"
        done
    fi
    rm -rf "${ROOT}/share/man" "${ROOT}/share/ri"
    "${ROOT}/bin/ruby" -ropenssl -rpsych -rfiddle -rzlib -e 'puts RUBY_DESCRIPTION, OpenSSL::OPENSSL_LIBRARY_VERSION'
    package_artifact ruby "${major}" "${version}" "${ROOT}" '{
        "displayName": "Ruby", "category": "language",
        "links": {"bin": ["bin/ruby", "bin/gem", "bin/bundle", "bin/bundler", "bin/irb", "bin/rake", "bin/erb"]},
        "shims": ["ruby", "gem", "bundle", "bundler", "irb", "rake", "erb"]
    }'
}
