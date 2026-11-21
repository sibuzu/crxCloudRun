#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$root/utils/crx_docker_common.sh"
release_repo="${CRX_CLOUD_RUN_REPO:-https://github.com/sibuzu/crxCloudRun.git}"

usage() {
    printf 'Usage: %s <server-name> <branch>\nExample: %s pu30 20261121\n' "${0##*/}" "${0##*/}"
}

if (($# == 0)) || [[ "${1:-}" == --help || "${1:-}" == -h ]]; then usage; exit 0; fi
if (($# > 2)); then usage >&2; exit 2; fi
crx_select_server "$1"
if (($# == 1)); then
    usage
    printf '\nAvailable release branches (newest version first):\n'
    git ls-remote --heads "$release_repo" | sed 's|^.*refs/heads/||' | sort -Vr
    exit 0
fi

branch="$2"
git check-ref-format --branch "$branch" >/dev/null
if docker container inspect "$container_name" >/dev/null 2>&1; then
    printf 'Container %s already exists.\n' "$container_name" >&2
    exit 1
fi

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

staging="$(mktemp -d)"
trap 'rm -r -- "$staging"' EXIT
git clone --quiet --no-local --depth 1 --single-branch --branch "$branch" -- "$release_repo" "$staging/release"
[[ "$(git -C "$staging/release" symbolic-ref HEAD)" == "refs/heads/$branch" ]]
revision="$(git -C "$staging/release" rev-parse HEAD)"
image="crxcloudrun:${revision:0:12}"
docker build --tag "$image" --label "org.opencontainers.image.revision=$revision" "$staging/release"

mounts=()
for pair in log:Log quotes:Quotes kline:Kline; do
    volume="$volume_prefix-${pair%:*}"
    if owner="$(docker volume inspect --format "{{ index .Labels \"$owner_label\" }}" "$volume" 2>/dev/null)"; then
        [[ "$owner" == "$container_name" ]] || { printf 'Volume %s belongs to another deployment.\n' "$volume" >&2; exit 1; }
    else
        docker volume create --label "$owner_label=$container_name" "$volume" >/dev/null
    fi
    mounts+=(--mount "type=volume,source=$volume,target=/app/${pair#*:}")
done

docker run -d --init --name "$container_name" --hostname "$container_name" \
    --network "$network" --restart unless-stopped --stop-timeout 35 \
    --log-driver json-file --log-opt max-size=10m --log-opt max-file=3 \
    --label "$owner_label=$container_name" --label "org.opencontainers.image.revision=$revision" \
    --env CRX_LOCAL_URL --env CRX_LOCAL_TOKEN --env CRX_TELEGRAM_URL --env CRX_COINBASE_WS_URL \
    --env "CRX_BUILD_BRANCH=$branch" "${mounts[@]}" "$image" "$server_id" >/dev/null

printf '%s started with branch %s (%s), Server ID %s.\n' "$container_name" "$branch" "${revision:0:12}" "$server_id"
