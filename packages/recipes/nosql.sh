#!/bin/bash
# NoSQL, search and object storage: MongoDB (+ mongosh), Meilisearch and Typesense as official
# vendor builds, MinIO built from its last released source.

build_mongodb() {
    local major="$1" source="mongodb-$1-${ARCH}" version src shell
    version="$(source_field "${source}" 2)"
    log "Packaging MongoDB ${version} (${ARCH})"
    stage_prefix mongodb "${major}" "${version}"
    src="$(unpack "${source}")"
    mkdir -p "${ROOT}/bin" "${ROOT}/share"
    install -m 0755 "${src}/bin/mongod" "${src}/bin/mongos" "${ROOT}/bin/"
    cp "${src}"/LICENSE* "${src}"/THIRD-PARTY-NOTICES* "${ROOT}/share/" 2>/dev/null || true
    printf 'MongoDB Community Server %s (SSPL). Corresponding source:\nhttps://github.com/mongodb/mongo/tree/r%s\n' \
        "${version}" "${version}" >"${ROOT}/share/SOURCE.txt"
    # The shell is a separate project (Apache 2.0); bundled so every server version has a client.
    shell="mongosh-${ARCH}"
    unpack_flat "${shell}" "${SRC}/mongosh"
    install -m 0755 "${SRC}"/mongosh/mongosh-*/bin/mongosh "${ROOT}/bin/mongosh"
    "${ROOT}/bin/mongod" --version | sed -n 1p
    "${ROOT}/bin/mongosh" --version
    package_artifact mongodb "${major}" "${version}" "${ROOT}" '{
        "displayName": "MongoDB", "category": "nosql", "service": "mongodb",
        "links": {"bin": ["bin/mongod", "bin/mongosh"]}
    }'
}

build_meilisearch() {
    local major="1" source="meilisearch-${ARCH}" version file
    version="$(source_field "${source}" 2)"
    log "Packaging Meilisearch ${version} (${ARCH})"
    stage_prefix meilisearch "${major}" "${version}"
    file="$(fetch "${source}")"
    mkdir -p "${ROOT}/bin"
    install -m 0755 "${file}" "${ROOT}/bin/meilisearch"
    "${ROOT}/bin/meilisearch" --version
    package_artifact meilisearch "${major}" "${version}" "${ROOT}" '{
        "displayName": "Meilisearch", "category": "nosql", "service": "meilisearch",
        "links": {"bin": ["bin/meilisearch"]}
    }'
}

build_typesense() {
    local major="30" source="typesense-${ARCH}" version
    version="$(source_field "${source}" 2)"
    log "Packaging Typesense ${version} (${ARCH})"
    stage_prefix typesense "${major}" "${version}"
    fetch typesense-src >/dev/null # GPL: mirrored next to the binaries on publish
    unpack_flat "${source}" "${SRC}/typesense"
    mkdir -p "${ROOT}/bin" "${ROOT}/share"
    install -m 0755 "${SRC}/typesense/typesense-server" "${ROOT}/bin/typesense-server"
    printf 'Typesense %s (GPL-3.0). Corresponding source: typesense-src-v%s.tar.gz in the EasyServ package release,\nupstream https://github.com/typesense/typesense/tree/v%s\n' \
        "${version}" "${version}" "${version}" >"${ROOT}/share/SOURCE.txt"
    { "${ROOT}/bin/typesense-server" --version 2>&1 || true; } | sed -n 1p # exits 1 after printing
    package_artifact typesense "${major}" "${version}" "${ROOT}" '{
        "displayName": "Typesense", "category": "nosql", "service": "typesense",
        "links": {"bin": ["bin/typesense-server"]}
    }'
}

build_minio() {
    local major="2025" version src gobin tag
    version="$(source_field minio 2)"
    tag="$(basename "$(source_field minio 3)" .tar.gz)"
    log "Building MinIO ${tag} (${ARCH})"
    rm -f "${LOGS}/minio.log"
    stage_prefix minio "${major}" "${version}"
    # Host Go toolchain from the Go package sources (never linked into the result).
    gobin="$(ARCH="$(uname -m)" unpack "go-1.27-$(uname -m)")/bin"
    src="$(unpack minio)"
    local release="${tag#RELEASE.}"
    local stamp="${release%%T*}T$(echo "${release#*T}" | tr '-' ':')"
    (
        cd "${src}"
        export PATH="${gobin}:${PATH}" GOPATH="${WORK}/gopath" GOCACHE="${WORK}/gocache" GOFLAGS="-modcacherw"
        export CGO_ENABLED=0 GOOS=darwin GOARCH="$(go_arch)" GOTOOLCHAIN=local
        run_logged minio go build -trimpath -tags kqueue -o minio -ldflags "-s -w \
            -X github.com/minio/minio/cmd.Version=${stamp} \
            -X github.com/minio/minio/cmd.CopyrightYear=${release%%-*} \
            -X github.com/minio/minio/cmd.ReleaseTag=${tag} \
            -X github.com/minio/minio/cmd.CommitID=${tag} \
            -X github.com/minio/minio/cmd.ShortCommitID=${tag}"
    )
    mkdir -p "${ROOT}/bin" "${ROOT}/share"
    install -m 0755 "${src}/minio" "${ROOT}/bin/minio"
    cp "${src}/LICENSE" "${ROOT}/share/LICENSE"
    printf 'MinIO %s (AGPL-3.0). Corresponding source: minio-%s.tar.gz in the EasyServ package release.\n' \
        "${tag}" "${tag}" >"${ROOT}/share/SOURCE.txt"
    "${ROOT}/bin/minio" --version | sed -n 1p
    package_artifact minio "${major}" "${version}" "${ROOT}" '{
        "displayName": "MinIO", "category": "nosql", "service": "minio",
        "links": {"bin": ["bin/minio"]}
    }'
}
