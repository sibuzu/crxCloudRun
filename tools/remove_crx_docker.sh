#!/usr/bin/env bash
set -euo pipefail

tool_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$tool_dir/crx_docker_common.sh"
usage() { printf 'Usage: %s [-y] <server-name>\n' "${0##*/}"; }

confirm=1
case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    -y) confirm=0; shift ;;
esac
if (($# != 1)); then usage >&2; exit 2; fi
crx_select_server "$1"
docker info --format '{{.ServerVersion}}' >/dev/null
has_container=0
if owner="$(docker inspect --type container --format "{{ index .Config.Labels \"$owner_label\" }}" "$container_name" 2>/dev/null)"; then
    [[ "$owner" == "$container_name" ]] || { printf '%s is not managed by crxCloudRun.\n' "$container_name" >&2; exit 1; }
    has_container=1
fi

volumes=()
for kind in log quotes kline; do
    volume="$volume_prefix-$kind"
    if owner="$(docker volume inspect --format "{{ index .Labels \"$owner_label\" }}" "$volume" 2>/dev/null)"; then
        [[ "$owner" == "$container_name" ]] || { printf 'Volume %s belongs to another deployment.\n' "$volume" >&2; exit 1; }
        volumes+=("$volume")
    fi
done
if ((!has_container && !${#volumes[@]})); then printf 'No crxCloudRun resources found for %s.\n' "$container_name"; exit 0; fi

if ((has_container)); then printf 'Container: %s\n' "$container_name"; fi
if ((${#volumes[@]})); then printf 'Volume: %s\n' "${volumes[@]}"; fi
if ((confirm)); then
    read -r -p 'Remove these resources and their stored data? [y/N] ' answer || exit 1
    if [[ "${answer,,}" != y && "${answer,,}" != yes ]]; then printf 'Cancelled.\n'; exit 0; fi
fi

if ((has_container)); then
    docker stop --time 35 "$container_name" >/dev/null
    docker container rm "$container_name" >/dev/null
fi
if ((${#volumes[@]})); then docker volume rm "${volumes[@]}" >/dev/null; fi
printf 'Removed crxCloudRun resources for %s.\n' "$container_name"
