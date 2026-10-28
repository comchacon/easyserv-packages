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
| Python (python-build-standalone) | PSF-2.0 | https://github.com/astral-sh/python-build-standalone |
| Ruby | Ruby License / BSD-2-Clause | https://www.ruby-lang.org |
| Go | BSD-3-Clause | https://go.dev |
| Java (Eclipse Temurin) | GPL-2.0 with Classpath Exception | https://adoptium.net (source: https://github.com/adoptium) |
| Bun | MIT | https://bun.sh |
| Deno | MIT | https://deno.com |
| MongoDB Community Server | SSPL-1.0 | https://github.com/mongodb/mongo (`share/SOURCE.txt` names the tag) |
| mongosh | Apache-2.0 | https://github.com/mongodb-js/mongosh |
| Meilisearch | MIT | https://www.meilisearch.com |
| Typesense | GPL-3.0 | https://typesense.org |
| MinIO (last community release, upstream archived) | AGPL-3.0 | https://github.com/minio/minio |
| frp client (frpc) | Apache-2.0 | https://github.com/fatedier/frp |
| cloudflared (signed by Cloudflare) | Apache-2.0 | https://github.com/cloudflare/cloudflared |
| libyaml (statically linked into Ruby and the PHP yaml extension) | MIT | https://github.com/yaml/libyaml |
| PHP extensions from PECL: igbinary, msgpack, apcu, redis, memcached, pcov, yaml | PHP-3.01 / BSD | https://pecl.php.net |
| Xdebug | Xdebug License (PHP-3.01 based) | https://xdebug.org |
| MongoDB PHP driver (incl. libmongoc/libbson) | Apache-2.0 | https://github.com/mongodb/mongo-php-driver |
| libpq (statically linked into pgsql/pdo_pgsql) | PostgreSQL License | https://www.postgresql.org |
| libmemcached-awesome (statically linked into memcached) | BSD-3-Clause | https://github.com/awesomized/libmemcached |
| tidy-html5 (statically linked into tidy) | W3C | https://github.com/htacg/tidy-html5 |
| GMP (statically linked into the gmp extension) | LGPL-3.0 | https://gmplib.org |
| libintl from GNU gettext (statically linked into the gettext extension) | LGPL-2.1 | https://www.gnu.org/software/gettext/ |
| OpenSSL (statically linked) | Apache-2.0 | https://www.openssl.org |
| ICU (statically linked) | Unicode License v3 | https://icu.unicode.org |

The exact upstream versions and source checksums are recorded in `packages/sources.lock` of the
EasyServ source repository. The corresponding source archives of the GPL/AGPL/LGPL components built or mirrored by EasyServ (MariaDB,
MySQL, dnsmasq, acme.sh, Typesense, MinIO, GMP, gettext) are attached to the same release; the PHP build recipe
(`packages/recipes/php.sh`) allows relinking the LGPL libraries into the extension modules.

## Build recipes

The `packages/` directory contains the complete build scripts used to produce every archive
(`packages/build.sh`, `packages/recipes/`, `packages/lib/`), including the pinned upstream sources
in `packages/sources.lock`. Build on macOS with Xcode installed:

```sh
brew install pkgconf cmake
packages/build.sh nginx php-8.5
```
