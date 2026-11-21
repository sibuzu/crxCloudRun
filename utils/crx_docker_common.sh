#!/usr/bin/env bash

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
