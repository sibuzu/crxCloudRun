#!/usr/bin/env bash
set -euo pipefail

if (($#)); then
    case "$1" in
        -h|--help) printf 'Usage: %s\nList unused local Docker volumes before confirming removal.\n' "${0##*/}"; exit 0 ;;
        *) printf 'Usage: %s\n' "${0##*/}" >&2; exit 2 ;;
    esac
fi

volume_names="$(docker volume ls --format '{{.Name}}')"
volumes=()
if [[ -n "$volume_names" ]]; then mapfile -t volumes <<<"$volume_names"; fi

unused_names="$(docker volume ls --filter driver=local --filter dangling=true --format '{{.Name}}')"
unused=()
if [[ -n "$unused_names" ]]; then mapfile -t unused <<<"$unused_names"; fi

printf 'Total Docker volumes: %d\n' "${#volumes[@]}"
printf 'Unused local volumes to remove: %d\n' "${#unused[@]}"
if ((!${#unused[@]})); then exit 0; fi
printf '  %s\n' "${unused[@]}"

if ! read -r -p 'Delete the listed volumes? [y/N] ' answer ||
   [[ "${answer,,}" != y && "${answer,,}" != yes ]]; then
    printf 'Cancelled.\n'
    exit 0
fi

exec docker volume rm -- "${unused[@]}"
