#!/bin/bash
# -----------------------------------------------------------------------------
# EasyServ package build library.
#
# Packages are built for the fixed install location
#   /Applications/EasyServ/package/<name>/<major>/<version>
# and staged with DESTDIR, so building never needs root. Third-party libraries
# (OpenSSL, ICU, libzip, …) are built as static libraries into a per-arch deps
# prefix and linked statically; the resulting binaries only depend on macOS
# system libraries.
# -----------------------------------------------------------------------------
set -euo pipefail

PKG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "${PKG_ROOT}/.." && pwd)"

ARCH="${ARCH:-$(uname -m)}"
INSTALL_ROOT="/Applications/EasyServ/package"
ETC_ROOT="/Applications/EasyServ/etc"
MIN_MACOS="13.0"

WORK="${REPO_ROOT}/build/packages"
CACHE="${WORK}/cache"
SRC="${WORK}/src/${ARCH}"
DEPS="${WORK}/deps/${ARCH}"
STAGE="${WORK}/stage/${ARCH}"
DIST="${WORK}/dist"
LOGS="${WORK}/logs/${ARCH}"
TOOLS="${WORK}/tools/bin"

JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"

case "${ARCH}" in
arm64) HOST_TRIPLE="aarch64-apple-darwin" ;;
x86_64) HOST_TRIPLE="x86_64-apple-darwin" ;;
*) echo "Unsupported ARCH ${ARCH}" >&2; exit 1 ;;
esac

mkdir -p "${CACHE}" "${SRC}" "${DEPS}" "${STAGE}" "${DIST}" "${LOGS}" "${TOOLS}"

# Build tools only (never linked): pkgconf and cmake from Homebrew, exposed through a private
# bin directory so nothing else from /opt/homebrew or other dev environments leaks into builds.
for tool in pkgconf cmake; do
    if [[ ! -x "${TOOLS}/${tool}" ]]; then
        found="$(PATH="/opt/homebrew/bin:/usr/local/bin" command -v "${tool}" || true)"
        [[ -n "${found}" ]] || { echo "Missing build tool ${tool} (brew install ${tool})" >&2; exit 1; }
        ln -sf "${found}" "${TOOLS}/${tool}"
    fi
done
ln -sf pkgconf "${TOOLS}/pkg-config"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="${TOOLS}:${DEVELOPER_DIR}/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin"
unset CPATH LIBRARY_PATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH PKG_CONFIG_PATH DYLD_LIBRARY_PATH
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
export MACOSX_DEPLOYMENT_TARGET="${MIN_MACOS}"
export CC="$(xcrun -f clang) -arch ${ARCH}"
export CXX="$(xcrun -f clang++) -arch ${ARCH}"
export CFLAGS="-O2 -arch ${ARCH} -mmacosx-version-min=${MIN_MACOS}"
export CXXFLAGS="${CFLAGS}"
export CPPFLAGS="-I${DEPS}/include"
export LDFLAGS="-arch ${ARCH} -L${DEPS}/lib -mmacosx-version-min=${MIN_MACOS}"
export PKG_CONFIG_LIBDIR="${DEPS}/lib/pkgconfig:${DEPS}/share/pkgconfig"
export PKG_CONFIG_PATH=""

log() { printf '\033[1m==> %s\033[0m\n' "$*"; }

# macOS ships these libraries (in the SDK / dyld cache) without pkg-config files; configure scripts
# and the static .pc files of our deps require them. Versions only need to satisfy minimums.
mkdir -p "${DEPS}/lib/pkgconfig"
for system_lib in "zlib:z:1.2.12:" "bzip2:bz2:1.0.8:" "sqlite3:sqlite3:3.43.2:" "libcurl:curl:8.7.1:" \
    "libxml-2.0:xml2:2.9.13:-I${SDKROOT}/usr/include/libxml2" "libedit:edit:3.1:"; do
    IFS=: read -r pc_name lib_name lib_version cflags <<<"${system_lib}"
    printf 'Name: %s\nDescription: %s from the macOS SDK\nVersion: %s\nLibs: -l%s\nCflags: %s\n' \
        "${pc_name}" "${pc_name}" "${lib_version}" "${lib_name}" "${cflags}" >"${DEPS}/lib/pkgconfig/${pc_name}.pc"
done

# source_field <name> <column> – column 2 = version, 3 = url, 4 = sha256
source_field() {
    awk -v n="$1" -v c="$2" '$1 == n { print $c }' "${PKG_ROOT}/sources.lock"
}

# fetch <name> -> path of verified tarball in the cache
fetch() {
    local name="$1" url sha file
    url="$(source_field "${name}" 3)"
    sha="$(source_field "${name}" 4)"
    [[ -n "${url}" && -n "${sha}" ]] || { echo "No source entry for ${name}" >&2; exit 1; }
    file="${CACHE}/$(basename "${url}")"
    if [[ ! -f "${file}" ]] || [[ "$(shasum -a 256 "${file}" | cut -d' ' -f1)" != "${sha}" ]]; then
        log "Downloading ${url}" >&2
        # Command substitution does not inherit errexit in bash 3.2 – fail explicitly.
        /usr/bin/curl -fL --retry 5 --retry-all-errors --connect-timeout 30 -o "${file}.part" "${url}" ||
            { echo "Download failed: ${url}" >&2; exit 1; }
        mv "${file}.part" "${file}"
    fi
    local actual
    actual="$(shasum -a 256 "${file}" | cut -d' ' -f1)"
    if [[ "${actual}" != "${sha}" ]]; then
        echo "Checksum mismatch for ${name}: expected ${sha}, got ${actual}" >&2
        exit 1
    fi
    echo "${file}"
}

# unpack <name> -> fresh source directory
unpack() {
    local name="$1" tarball dir
    tarball="$(fetch "${name}")" || exit 1
    dir="${SRC}/${name}"
    rm -rf "${dir}"
    mkdir -p "${dir}"
    tar -xf "${tarball}" -C "${dir}" --strip-components 1
    echo "${dir}"
}

# unpack_flat <name> <dir> – for archives without a top-level directory (vendor binaries)
unpack_flat() {
    local name="$1" dir="$2" tarball
    tarball="$(fetch "${name}")" || exit 1
    rm -rf "${dir}"
    mkdir -p "${dir}"
    tar -xf "${tarball}" -C "${dir}"
}

# build_tool <name> – host build tools (e.g. bison) installed into the private tools prefix
build_tool_bison() {
    [[ -x "${TOOLS}/bison" ]] && return 0
    local src prefix="${WORK}/tools"
    log "Building build tool bison"
    src="$(ARCH="$(uname -m)" unpack bison)"
    (
        cd "${src}"
        run_logged tool-bison env -u CFLAGS -u LDFLAGS -u CPPFLAGS CC="$(xcrun -f clang)" ./configure --prefix="${prefix}" --disable-nls
        run_logged tool-bison make -j"${JOBS}"
        run_logged tool-bison make install
    )
}

# run_logged <logname> <command...> – full output goes to the log, tail on failure
run_logged() {
    local logfile="${LOGS}/$1.log"
    shift
    if ! "$@" >>"${logfile}" 2>&1; then
        echo "Command failed: $*" >&2
        tail -40 "${logfile}" >&2
        exit 1
    fi
}

# dep_built <name> – marker check so static deps are built once per arch
dep_built() { [[ -f "${DEPS}/.built-$1-$(source_field "$1" 2)" ]]; }
mark_dep_built() { touch "${DEPS}/.built-$1-$(source_field "$1" 2)"; }

# Mach-O files may only link against macOS system libraries and libraries inside their own
# package (absolute install prefix or @loader_path/@executable_path/@rpath).
check_linkage() {
    local root="$1" prefix="$2" file bad=0
    while IFS= read -r -d '' file; do
        file -b "${file}" | grep -q "Mach-O" || continue
        while read -r lib; do
            case "${lib}" in
            /usr/lib/* | /System/Library/* | "${prefix}"/* | @loader_path/* | @executable_path/* | @rpath/*) ;;
            *)
                echo "Disallowed dependency in ${file#"${root}"/}: ${lib}" >&2
                bad=1
                ;;
            esac
        done < <(otool -L "${file}" | tail -n +2 | awk '{print $1}' | grep -v "^${file}")
    done < <(find "${root}" -type f -perm -u+x -print0)
    return "${bad}"
}

# package_artifact <name> <major> <version> <stage_dir> <manifest_extra_json>
# Creates dist/<name>-<version>-<arch>.tar.gz containing "<version>/…" incl. easyserv-package.json.
package_artifact() {
    local name="$1" major="$2" version="$3" root="$4" extra="${5:-}"
    [[ -n "${extra}" ]] || extra='{}'
    local manifest="${root}/easyserv-package.json"

    log "Checking linkage of ${name} ${version}"
    check_linkage "${root}" "${INSTALL_ROOT}/${name}/${major}/${version}"

    /usr/bin/python3 - "${manifest}" "${name}" "${major}" "${version}" "${ARCH}" "${MIN_MACOS}" "${extra}" <<'EOF'
import json, sys, datetime
path, name, major, version, arch, min_macos, extra = sys.argv[1:]
manifest = {
    "schema": 1,
    "name": name,
    "major": major,
    "version": version,
    "arch": arch,
    "minMacOS": min_macos,
    "builtAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}
manifest.update(json.loads(extra))
with open(path, "w") as f:
    json.dump(manifest, f, indent=2, sort_keys=True)
    f.write("\n")
EOF

    local artifact="${DIST}/${name}-${version}-${ARCH}.tar.gz"
    local parent
    parent="$(dirname "${root}")"
    log "Packaging ${artifact#"${REPO_ROOT}"/}"
    COPYFILE_DISABLE=1 tar --uid 0 --gid 0 --uname root --gname wheel -czf "${artifact}" -C "${parent}" "$(basename "${root}")"
    cp "${manifest}" "${DIST}/${name}-${version}-${ARCH}.json"
    du -h "${artifact}" | cut -f1 | xargs printf '    size %s\n'
}
