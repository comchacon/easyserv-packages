#!/bin/bash
# Build EasyServ packages.
#
#   packages/build.sh nginx php-8.5           → build/packages/dist/<name>-<version>-<arch>.tar.gz
#   packages/build.sh all                     → every package below
#   ARCH=x86_64 packages/build.sh nginx
#
# Then generate and sign the catalog (make catalog, see packages/README.md).

source "$(dirname "$0")/lib/common.sh"
for recipe in deps nginx php services databases vendor languages nosql tunnels; do
    source "${PKG_ROOT}/recipes/${recipe}.sh"
done

ALL="nginx apache php-8.5 php-8.4 dnsmasq memcached redis postgresql-18 postgresql-17 mariadb-11.4 mysql-8.4
     node-24 node-22 caddy mailpit composer acme-sh phpmyadmin adminer
     python-3.14 python-3.13 python-3.12 ruby-4.0 ruby-3.4 go-1.27 go-1.26 java-25 java-21 bun deno
     mongodb-9.0 mongodb-8.0 meilisearch typesense minio frpc cloudflared"

[[ $# -gt 0 ]] || { echo "Usage: $0 <package…|all>  (${ALL//$'\n'/ })" >&2; exit 2; }
[[ "$1" == "all" ]] && set -- ${ALL}

for target in "$@"; do
    case "${target}" in
    nginx) build_nginx ;;
    apache) build_apache ;;
    php-*) build_php "${target}" ;;
    dnsmasq | memcached | redis | caddy | mailpit | composer | phpmyadmin | adminer | bun | deno | meilisearch | typesense | minio | frpc | cloudflared)
        "build_${target}" ;;
    acme-sh) build_acme_sh ;;
    postgresql-*) build_postgresql "${target}" ;;
    mariadb-*) build_mariadb "${target}" ;;
    mysql-*) build_mysql "${target}" ;;
    node-*) build_node "${target#node-}" ;;
    python-*) build_python "${target#python-}" ;;
    ruby-*) build_ruby "${target#ruby-}" ;;
    go-*) build_go "${target#go-}" ;;
    java-*) build_java "${target#java-}" ;;
    mongodb-*) build_mongodb "${target#mongodb-}" ;;
    *) echo "Unknown package ${target}" >&2; exit 2 ;;
    esac
done
