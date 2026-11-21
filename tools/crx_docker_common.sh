#!/usr/bin/env bash

release_repo="${CRX_CLOUD_RUN_REPO:-https://github.com/sibuzu/crxCloudRun.git}"
volume_dirs=(Log Quotes Kline)

crx_source_root() {
    local source_dir="${CRX_NEBULA_DIR:-$1/..}"
    if [[ ! -f "$source_dir/crxServer/crxServer.csproj" || ! -f "$source_dir/crxPacker/crxPacker.csproj" ]]; then
        printf 'crxNebula source checkout not found at %s. Set CRX_NEBULA_DIR to its path.\n' "$source_dir" >&2
        return 1
    fi
    (cd -- "$source_dir" && pwd)
}

crx_select_server() {
    server_name="${1,,}"
    server_name="${server_name#crx-}"
    [[ "$server_name" =~ ^[a-z0-9]([a-z0-9-]{0,49}[a-z0-9])?$ ]] || {
        printf 'Invalid server name: %s\n' "$1" >&2
        return 2
    }
    container_name="crx-$server_name"
    server_id="${server_name^^}"
    volume_prefix="crxcloudrun-$server_name"
    owner_label="io.github.sibuzu.crxcloudrun.server"
}

crx_inspect_container() {
    if container_id="$(docker container inspect --format '{{.Id}}' "$container_name" 2>/dev/null)"; then
        local owner
        owner="$(docker container inspect --format "{{ index .Config.Labels \"$owner_label\" }}" "$container_id")"
        if [[ "$owner" != "$container_name" ]]; then
            printf '%s is not managed by crxCloudRun.\n' "$container_name" >&2
            return 1
        fi
    else
        docker info --format '{{.ServerVersion}}' >/dev/null
    fi
}

crx_find_volumes() {
    volumes=()
    local directory volume owner
    for directory in "${volume_dirs[@]}"; do
        volume="$volume_prefix-${directory,,}"
        if owner="$(docker volume inspect --format "{{ index .Labels \"$owner_label\" }}" "$volume" 2>/dev/null)"; then
            if [[ "$owner" != "$container_name" ]]; then
                printf 'Volume %s belongs to another deployment.\n' "$volume" >&2
                return 1
            fi
            volumes+=("$volume")
        fi
    done
}

crx_check_volume_users() {
    local volume users user_id
    for volume in "${volumes[@]}"; do
        users="$(docker container ls --all --quiet --no-trunc --filter "volume=$volume")"
        while IFS= read -r user_id; do
            if [[ -n "$user_id" && "$user_id" != "$container_id" ]]; then
                printf 'Volume %s is used by another container.\n' "$volume" >&2
                return 1
            fi
        done <<<"$users"
    done
}

crx_fetch_release() {
    git check-ref-format --branch "$branch" >/dev/null
    staging="$(mktemp -d)"
    trap 'rm -r -- "$staging"' EXIT
    git clone --quiet --no-local --depth 1 --single-branch --branch "$branch" -- "$release_repo" "$staging/release"
    [[ "$(git -C "$staging/release" symbolic-ref HEAD)" == "refs/heads/$branch" ]]
    revision="$(git -C "$staging/release" rev-parse HEAD)"
    image="crxcloudrun:${revision:0:12}"
}

crx_build_release() {
    docker build --tag "$image" --label "org.opencontainers.image.revision=$revision" "$staging/release"
}

crx_ensure_mounts() {
    mounts=()
    local directory volume
    for directory in "${volume_dirs[@]}"; do
        volume="$volume_prefix-${directory,,}"
        docker volume create --label "$owner_label=$container_name" "$volume" >/dev/null
        mounts+=(--mount "type=volume,source=$volume,target=/app/$directory")
    done
}

crx_make_container() {
    docker container create --init --name "$container_name" --hostname "$container_name" \
        --network "$network" --dns "$dns" --restart unless-stopped --stop-timeout 35 \
        --log-driver json-file --log-opt max-size=10m --log-opt max-file=3 \
        --label "$owner_label=$container_name" --label "org.opencontainers.image.revision=$revision" \
        --env CRX_LOCAL_URL --env CRX_LOCAL_TOKEN --env CRX_TELEGRAM_URL --env CRX_COINBASE_WS_URL \
        --env "CRX_BUILD_BRANCH=$branch" "${mounts[@]}" "$image" "$server_id"
}

crx_start_container() {
    local id="$1" state
    docker start "$id" >/dev/null || return 1
    sleep 1
    state="$(docker container inspect --format '{{.State.Status}} {{.RestartCount}}' "$id")" || return 1
    if [[ "$state" != 'running 0' ]]; then
        printf 'Container %s did not stay running after start (%s).\n' "$container_name" "$state" >&2
        return 1
    fi
}
