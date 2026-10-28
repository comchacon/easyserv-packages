# Tunnel clients (Phase 5c). Official release binaries; ngrok is proprietary and not redistributed.

build_frpc() {
    local major="0" source="frp-${ARCH}" version
    version="$(source_field "${source}" 2)"
    log "Packaging frpc ${version} (${ARCH})"
    stage_prefix frpc "${major}" "${version}"
    unpack_flat "${source}" "${SRC}/frp"
    mkdir -p "${ROOT}/bin" "${ROOT}/share"
    install -m 0755 "${SRC}"/frp/frp_*/frpc "${ROOT}/bin/frpc"
    install -m 0644 "${SRC}"/frp/frp_*/LICENSE "${ROOT}/share/LICENSE"
    "${ROOT}/bin/frpc" --version
    package_artifact frpc "${major}" "${version}" "${ROOT}" '{
        "displayName": "frp (Client)", "category": "tunnel",
        "links": {"bin": ["bin/frpc"]}
    }'
}

build_cloudflared() {
    local major="2026" source="cloudflared-${ARCH}" version
    version="$(source_field "${source}" 2)"
    log "Packaging cloudflared ${version} (${ARCH})"
    stage_prefix cloudflared "${major}" "${version}"
    unpack_flat "${source}" "${SRC}/cloudflared"
    mkdir -p "${ROOT}/bin"
    install -m 0755 "${SRC}/cloudflared/cloudflared" "${ROOT}/bin/cloudflared"
    # Keep Cloudflare's Developer ID signature: no strip, no re-signing.
    codesign --verify --strict "${ROOT}/bin/cloudflared"
    "${ROOT}/bin/cloudflared" --version
    package_artifact cloudflared "${major}" "${version}" "${ROOT}" '{
        "displayName": "Cloudflare Tunnel (cloudflared)", "category": "tunnel",
        "links": {"bin": ["bin/cloudflared"]}
    }'
}
