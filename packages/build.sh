#!/bin/bash
# Build EasyServ packages.
#
#   packages/build.sh nginx php-8.5           → build/packages/dist/<name>-<version>-<arch>.tar.gz
#   packages/build.sh all                     → every package below
#   ARCH=x86_64 packages/build.sh nginx
#
# Then generate and sign the catalog (make catalog, see packages/README.md).

source "$(dirname "$0")/lib/common.sh"
for recipe in deps nginx php services databases vendor; do
    source "${PKG_ROOT}/recipes/${recipe}.sh"
done

ALL="nginx apache php-8.5 php-8.4 dnsmasq memcached redis postgresql-18 postgresql-17 mariadb-11.4 mysql-8.4
     node-24 node-22 caddy mailpit composer acme-sh phpmyadmin adminer"

[[ $# -gt 0 ]] || { echo "Usage: $0 <package…|all>  (${ALL//$'\n'/ })" >&2; exit 2; }
[[ "$1" == "all" ]] && set -- ${ALL}

for target in "$@"; do
    case "${target}" in
    nginx) build_nginx ;;
    apache) build_apache ;;
    php-*) build_php "${target}" ;;
    dnsmasq | memcached | redis | caddy | mailpit | composer | phpmyadmin | adminer) "build_${target}" ;;
    acme-sh) build_acme_sh ;;
    postgresql-*) build_postgresql "${target}" ;;
    mariadb-*) build_mariadb "${target}" ;;
    mysql-*) build_mysql "${target}" ;;
    node-*) build_node "${target#node-}" ;;
    *) echo "Unknown package ${target}" >&2; exit 2 ;;
    esac
done
