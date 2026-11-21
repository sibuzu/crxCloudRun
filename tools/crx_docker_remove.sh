#!/usr/bin/env bash
set -euo pipefail

tool_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$tool_dir/crx_docker_common.sh"
usage() { printf 'Usage: %s [--force] [-y] <server-name>\n' "${0##*/}"; }

confirm=1
force=0
while (($#)); do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -y) confirm=0 ;;
        --force) force=1 ;;
        *) break ;;
    esac
    shift
done
if (($# != 1)); then usage >&2; exit 2; fi
crx_select_server "$1"
crx_inspect_container
if [[ -n "$container_id" ]] && ((!force)); then
    running="$(docker container inspect --format '{{.State.Running}}' "$container_id")"
    if [[ "$running" == true ]]; then
        printf 'Container %s is running. Stop it first or use --force.\n' "$container_name" >&2
        exit 1
    fi
fi

crx_find_volumes
crx_check_volume_users
if [[ -z "$container_id" ]] && ((!${#volumes[@]})); then printf 'No crxCloudRun resources found for %s.\n' "$container_name"; exit 0; fi

if [[ -n "$container_id" ]]; then printf 'Container: %s\n' "$container_name"; fi
if ((${#volumes[@]})); then printf 'Volume: %s\n' "${volumes[@]}"; fi
if ((confirm)); then
    read -r -p 'Remove these resources and their stored data? [y/N] ' answer || exit 1
    if [[ "${answer,,}" != y && "${answer,,}" != yes ]]; then printf 'Cancelled.\n'; exit 0; fi
fi

if [[ -n "$container_id" ]]; then
    if ((force)); then docker stop --time 35 "$container_id" >/dev/null; fi
    docker container rm "$container_id" >/dev/null
fi
if ((${#volumes[@]})); then docker volume rm "${volumes[@]}" >/dev/null; fi
printf 'Removed crxCloudRun resources for %s.\n' "$container_name"
