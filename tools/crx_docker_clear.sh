#!/usr/bin/env bash
set -euo pipefail

if (($#)); then
    case "$1" in
        -h|--help) printf 'Usage: %s\nRemove all unused Docker volumes after confirmation.\n' "${0##*/}"; exit 0 ;;
        *) printf 'Usage: %s\n' "${0##*/}" >&2; exit 2 ;;
    esac
fi

exec docker volume prune --all
