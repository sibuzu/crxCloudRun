#!/usr/bin/env bash
set -euo pipefail

run_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$run_root/tools/crx_docker_common.sh"
release="${CRX_CLOUD_RUN_DIR:-$run_root}"
sdk="${CRX_BUILD_DOTNET:-dotnet}"

usage() {
    printf 'Usage: %s [--build | --rebuild | --full-build | --full-rebuild]\n' "${0##*/}"
}

if (($# > 1)); then usage >&2; exit 2; fi
case "${1:---build}" in
    --build) target=Build ;;
    --rebuild) target=Rebuild ;;
    --full-build) target=FullBuild ;;
    --full-rebuild) target=FullRebuild ;;
    --help|-h) usage; exit ;;
    *) usage >&2; exit 2 ;;
esac

root="$(crx_source_root "$run_root")"
mkdir -p -- "$release"
release="$(cd -- "$release" && pwd)"

cd -- "$root"
if command -v "$sdk" >/dev/null; then
    export CRX_CLOUD_RUN_DIR="$release"
    "$sdk" build crxServer -c Release -t:"$target"
    "$sdk" build crxPacker -c Release -t:"$target"
else
    mkdir -p crxServer/obj/docker-sdk
    docker run --rm --user "$(id -u):$(id -g)" \
        -e DOTNET_CLI_HOME=/src/crxServer/obj/docker-sdk \
        -e NUGET_PACKAGES=/src/crxServer/obj/docker-sdk/nuget \
        -e TZ="${TZ:-Asia/Taipei}" \
        -v "$root:/src" -v "$release:/src/crxCloudRun" -w /src \
        mcr.microsoft.com/dotnet/sdk:10.0.404 \
        sh -ec 'dotnet build crxServer -c Release -t:"$1" && dotnet build crxPacker -c Release -t:"$1"' sh "$target"
fi
printf 'Built Server and Packer to %s/app.\n' "$release"
