#!/usr/bin/env bash
set -euo pipefail

run_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$run_root/tools/crx_docker_common.sh"
root="${CRX_NEBULA_DIR:-$run_root/..}"

usage() {
    printf 'Usage: %s [--force] <server-name> [<branch> [--dns IP]]\nExample: %s pu30 20261121 --dns 1.1.1.1\nDefault DNS: 8.8.8.8\n' "${0##*/}" "${0##*/}"
}

if (($# == 0)) || [[ "${1:-}" == --help || "${1:-}" == -h ]]; then usage; exit 0; fi
force=0
if [[ "$1" == --force ]]; then force=1; shift; fi
if (($# == 0)); then usage >&2; exit 2; fi
dns=8.8.8.8
if (($# > 2)); then
    if (($# != 4)) || [[ "$3" != --dns ]]; then usage >&2; exit 2; fi
    dns="$4"
    if ! python3 -c 'import ipaddress, sys; ipaddress.ip_address(sys.argv[1])' "$dns" 2>/dev/null; then
        printf 'Invalid DNS server IP: %s\n' "$dns" >&2
        exit 2
    fi
fi
crx_select_server "$1"
if (($# == 1)); then
    usage
    printf '\nAvailable release branches (newest version first):\n'
    git ls-remote --heads "$release_repo" | sed 's|^.*refs/heads/||' | sort -Vr
    exit 0
fi

branch="$2"
crx_inspect_container
if [[ -n "$container_id" ]] && ((!force)); then
    printf 'Container %s already exists. Remove it first or use --force.\n' "$container_name" >&2
    exit 1
fi
crx_find_volumes
crx_check_volume_users

network="${CRX_DOCKER_NETWORK:-crxnebula-local_default}"
docker network inspect --format '{{.Name}}' "$network" >/dev/null
export CRX_LOCAL_URL="${CRX_LOCAL_URL:-http://crxdb:8080/}"
if [[ -z "${CRX_LOCAL_TOKEN:-}" ]]; then
    [[ "$(docker inspect --format '{{.State.Running}}' crxDB)" == true ]] || {
        printf 'Start crxDB before deploying a Server.\n' >&2; exit 1;
    }
    CRX_LOCAL_TOKEN="$(docker inspect --format '{{json .Config.Env}}' crxDB | python3 -c '
import json, sys
settings = dict(value.split("=", 1) for value in json.load(sys.stdin))
print(settings["CRX_LOCAL_TOKEN"])
')"
fi
export CRX_LOCAL_TOKEN="${CRX_LOCAL_TOKEN:?missing CRX_LOCAL_TOKEN}"

if [[ -z "${CRX_TELEGRAM_URL:-}" && -f "$root/.env" && -f "$root/docker/compose.yaml" ]]; then
    CRX_TELEGRAM_URL="$(docker compose --env-file "$root/.env" -f "$root/docker/compose.yaml" config --format json |
        python3 -c 'import json,sys; print(json.load(sys.stdin)["services"]["crxserver"]["environment"].get("CRX_TELEGRAM_URL", ""))')"
fi
export CRX_TELEGRAM_URL="${CRX_TELEGRAM_URL:-}"

crx_fetch_release
crx_build_release
if [[ -n "$container_id" ]]; then
    running="$(docker container inspect --format '{{.State.Running}}' "$container_id")"
    if [[ "$running" == true ]]; then docker stop --time 35 "$container_id" >/dev/null; fi
    docker container rm "$container_id" >/dev/null
fi
if ((${#volumes[@]})); then docker volume rm "${volumes[@]}" >/dev/null; fi

crx_ensure_mounts
new_id="$(crx_make_container)"
if ! crx_start_container "$new_id"; then
    docker container rm --force "$new_id" >/dev/null
    exit 1
fi
printf '%s started with branch %s (%s), Server ID %s.\n' "$container_name" "$branch" "${revision:0:12}" "$server_id"
