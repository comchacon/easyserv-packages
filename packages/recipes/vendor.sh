#!/bin/bash
# Official vendor builds repackaged as EasyServ packages (checksums pinned in sources.lock):
# Node.js, Caddy, Mailpit (Go binaries), Composer (phar), acme.sh (shell).

build_node() {
    local major="$1" source="node-$1-${ARCH}" version src
    version="$(source_field "${source}" 2)"
    log "Packaging Node.js ${version} (${ARCH})"
    stage_prefix node "${major}" "${version}"
    src="$(unpack "${source}")"
    mkdir -p "${ROOT}"
    cp -R "${src}/." "${ROOT}/"
    rm -rf "${ROOT}/share/doc" "${ROOT}/share/man" "${ROOT}/README.md" "${ROOT}/CHANGELOG.md"
    "${ROOT}/bin/node" --version
    package_artifact node "${major}" "${version}" "${ROOT}" '{
        "displayName": "Node.js", "category": "language",
        "links": {"bin": ["bin/node", "bin/npm", "bin/npx", "bin/corepack"]},
        "shims": ["node", "npm", "npx", "corepack"]
    }'
}

build_caddy() {
    local major="2" source="caddy-${ARCH}" version
    version="$(source_field "${source}" 2)"
    log "Packaging Caddy ${version} (${ARCH})"
    stage_prefix caddy "${major}" "${version}"
    mkdir -p "${ROOT}/bin" "${ROOT}/share"
    unpack_flat "${source}" "${SRC}/caddy"
    install -m 0755 "${SRC}/caddy/caddy" "${ROOT}/bin/caddy"
    cp "${SRC}/caddy/LICENSE" "${ROOT}/share/LICENSE"
    "${ROOT}/bin/caddy" version
    package_artifact caddy "${major}" "${version}" "${ROOT}" '{
        "displayName": "Caddy", "category": "webserver", "service": "caddy",
        "links": {"bin": ["bin/caddy"]}
    }'
}

build_mailpit() {
    local major="1" source="mailpit-${ARCH}" version
    version="$(source_field "${source}" 2)"
    log "Packaging Mailpit ${version} (${ARCH})"
    stage_prefix mailpit "${major}" "${version}"
    mkdir -p "${ROOT}/bin" "${ROOT}/share"
    unpack_flat "${source}" "${SRC}/mailpit"
    install -m 0755 "${SRC}/mailpit/mailpit" "${ROOT}/bin/mailpit"
    cp "${SRC}/mailpit/LICENSE" "${ROOT}/share/LICENSE" 2>/dev/null || true
    "${ROOT}/bin/mailpit" version | head -1
    package_artifact mailpit "${major}" "${version}" "${ROOT}" '{
        "displayName": "Mailpit", "category": "mail", "service": "mailpit",
        "links": {"bin": ["bin/mailpit"]}
    }'
}

build_composer() {
    local major="2" version phar
    version="$(source_field composer 2)"
    log "Packaging Composer ${version}"
    stage_prefix composer "${major}" "${version}"
    phar="$(fetch composer)"
    mkdir -p "${ROOT}/bin" "${ROOT}/libexec"
    install -m 0644 "${phar}" "${ROOT}/libexec/composer.phar"
    # Runs with the php found in PATH, i.e. the EasyServ shim honouring .php-version.
    cat >"${ROOT}/bin/composer" <<'EOF'
#!/bin/sh
# Resolve package/bin symlinks to the real location inside the package.
self="$0"
while [ -L "$self" ]; do
    link="$(readlink "$self")"
    case "$link" in /*) self="$link" ;; *) self="$(dirname "$self")/$link" ;; esac
done
here="$(cd "$(dirname "$self")" && pwd)"
exec php "$here/../libexec/composer.phar" "$@"
EOF
    chmod 0755 "${ROOT}/bin/composer"
    package_artifact composer "${major}" "${version}" "${ROOT}" '{
        "displayName": "Composer", "category": "tool",
        "links": {"bin": ["bin/composer"]}
    }'
}

build_acme_sh() {
    local major="3" version src
    version="$(source_field acme.sh 2)"
    log "Packaging acme.sh ${version}"
    stage_prefix acme-sh "${major}" "${version}"
    src="$(unpack acme.sh)"
    mkdir -p "${ROOT}/bin" "${ROOT}/libexec/acme.sh"
    cp -R "${src}/acme.sh" "${src}/dnsapi" "${src}/deploy" "${src}/notify" "${src}/LICENSE.md" "${ROOT}/libexec/acme.sh/"
    chmod 0755 "${ROOT}/libexec/acme.sh/acme.sh"
    cat >"${ROOT}/bin/acme.sh" <<'EOF'
#!/bin/sh
# Resolve package/bin symlinks to the real location inside the package.
self="$0"
while [ -L "$self" ]; do
    link="$(readlink "$self")"
    case "$link" in /*) self="$link" ;; *) self="$(dirname "$self")/$link" ;; esac
done
here="$(cd "$(dirname "$self")" && pwd)"
exec "$here/../libexec/acme.sh/acme.sh" --home "$here/../libexec/acme.sh" \
    --config-home /Applications/EasyServ/etc/acme "$@"
EOF
    chmod 0755 "${ROOT}/bin/acme.sh"
    package_artifact acme-sh "${major}" "${version}" "${ROOT}" '{
        "displayName": "acme.sh", "category": "tool",
        "links": {"bin": ["bin/acme.sh"]}
    }'
}
