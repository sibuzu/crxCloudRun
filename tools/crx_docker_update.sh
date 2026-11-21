#!/usr/bin/env bash
set -euo pipefail

tool_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$tool_dir/crx_docker_common.sh"
usage() { printf 'Usage: %s <server-name> [<branch>]\n' "${0##*/}"; }

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
esac
if (($# < 1 || $# > 2)); then usage >&2; exit 2; fi
crx_select_server "$1"
crx_inspect_container
if [[ -z "$container_id" ]]; then
    printf 'Container %s does not exist. Create it first.\n' "$container_name" >&2
    exit 1
fi

settings="$(docker container inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$container_id")"
unset CRX_LOCAL_URL CRX_LOCAL_TOKEN CRX_TELEGRAM_URL CRX_COINBASE_WS_URL
current_branch=
while IFS= read -r setting; do
    case "$setting" in
        CRX_BUILD_BRANCH=*) current_branch="${setting#*=}" ;;
        CRX_LOCAL_URL=*|CRX_LOCAL_TOKEN=*|CRX_TELEGRAM_URL=*|CRX_COINBASE_WS_URL=*) export "$setting" ;;
    esac
done <<<"$settings"
branch="${2:-$current_branch}"
if [[ -z "$branch" ]]; then
    printf 'No branch is recorded for %s. Specify a branch.\n' "$container_name" >&2
    exit 1
fi
current_revision="$(docker container inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' "$container_id")"
crx_fetch_release
reuse_image=false
if [[ "$branch" == "$current_branch" && "$revision" == "$current_revision" ]]; then
    group="$(docker container inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' "$container_id")"
    if [[ "$group" == "$server_group" ]]; then
        printf '%s already uses branch %s (%s).\n' "$container_name" "$branch" "${revision:0:12}"
        exit 0
    fi
    image="$(docker container inspect --format '{{.Image}}' "$container_id")"
    reuse_image=true
fi

backup_name="$container_name-update-backup"
if docker container inspect "$backup_name" >/dev/null 2>&1; then
    printf 'Backup container %s already exists.\n' "$backup_name" >&2
    exit 1
fi
network="$(docker container inspect --format '{{.HostConfig.NetworkMode}}' "$container_id")"
dns="$(docker container inspect --format '{{if .HostConfig.Dns}}{{index .HostConfig.Dns 0}}{{end}}' "$container_id")"
dns="${dns:-8.8.8.8}"
crx_find_volumes
if [[ "$reuse_image" == false ]]; then crx_build_release; fi
crx_ensure_mounts

running="$(docker container inspect --format '{{.State.Running}}' "$container_id")"
if [[ "$running" == true ]]; then docker stop --time 35 "$container_id" >/dev/null; fi
if ! docker rename "$container_id" "$backup_name"; then
    if [[ "$running" == true ]]; then docker start "$container_id" >/dev/null; fi
    exit 1
fi

if new_id="$(crx_make_container)"; then
    if [[ "$running" != true ]] || crx_start_container "$new_id"; then
        docker container rm "$container_id" >/dev/null
        printf '%s updated to branch %s (%s).\n' "$container_name" "$branch" "${revision:0:12}"
        exit 0
    fi
    docker container rm --force "$new_id" >/dev/null
fi

docker rename "$container_id" "$container_name"
if [[ "$running" == true ]]; then docker start "$container_id" >/dev/null; fi
printf 'Update failed. Restored the previous container %s.\n' "$container_name" >&2
exit 1
