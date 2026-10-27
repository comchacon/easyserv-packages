# EasyServ Packages

Prebuilt software packages for EasyServ, a local development environment for macOS.

The packages are published as assets of the rolling release **`packages`**. The EasyServ app reads
`catalog.json` from that release; the catalog is signed with Ed25519 (`catalog.json.sig`) and lists
the SHA-256 checksum of every archive. The app's privileged helper verifies the signature and
checksum before installing anything.

## Contents and licenses

All packages are built from unmodified upstream sources or repackaged from official vendor
releases. Each package keeps its upstream license:

| Package | License | Source |
|---|---|---|
| NGINX | BSD-2-Clause | https://nginx.org |
| PHP | PHP License 3.01 | https://www.php.net |
| PostgreSQL | PostgreSQL License | https://www.postgresql.org |
| MariaDB | GPL-2.0 | https://mariadb.org |
| MySQL Community Server | GPL-2.0 (with Universal FOSS Exception) | https://dev.mysql.com |
| Redis | RSALv2 / SSPLv1 / AGPLv3 (tri-license since Redis 8) | https://redis.io |
| Memcached | BSD-3-Clause | https://memcached.org |
| dnsmasq | GPL-2.0 / GPL-3.0 | https://thekelleys.org.uk/dnsmasq |
| Node.js | MIT | https://nodejs.org |
| Caddy | Apache-2.0 | https://caddyserver.com |
| Mailpit | MIT | https://mailpit.axllent.org |
| Composer | MIT | https://getcomposer.org |
| acme.sh | GPL-3.0 | https://github.com/acmesh-official/acme.sh |
| OpenSSL (statically linked) | Apache-2.0 | https://www.openssl.org |
| ICU (statically linked) | Unicode License v3 | https://icu.unicode.org |

The exact upstream versions and source checksums are recorded in `packages/sources.lock` of the
EasyServ source repository. The corresponding source archives of all GPL-licensed packages are
attached to the same release.

## Build recipes

The `packages/` directory contains the complete build scripts used to produce every archive
(`packages/build.sh`, `packages/recipes/`, `packages/lib/`), including the pinned upstream sources
in `packages/sources.lock`. Build on macOS with Xcode installed:

```sh
brew install pkgconf cmake
packages/build.sh nginx php-8.5
```
