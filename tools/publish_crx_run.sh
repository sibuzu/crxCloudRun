#!/usr/bin/env bash
set -euo pipefail

run_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$run_root/tools/crx_docker_common.sh"
release="${CRX_CLOUD_RUN_DIR:-$run_root}"
if (($# != 1)) || [[ "${1:-}" != [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]* ]]; then
    printf 'Usage: %s <dated-branch>\nExample: %s 20261121\n' "${0##*/}" "${0##*/}" >&2
    exit 2
fi
root="$(crx_source_root "$run_root")"
branch="$1"
git check-ref-format --branch "$branch" >/dev/null

runtime_paths=(utils/{CoinbaseSocket.py,BinanceKline.py,TestCoinbase.py,TestBinance.py,start_server.py})
tool_paths=(tools/{build_crx_run,publish_crx_run,crx_docker_clear,crx_docker_common,crx_docker_create,crx_docker_remove,crx_docker_update}.sh)
template_paths=(Dockerfile README.md .dockerignore .gitignore)
legacy_paths=(
    "${runtime_paths[@]#utils/}"
    {,tools/}{setup_crx_docker.sh,remove_crx_docker.sh}
    tools/crx_docker_setup.sh
    utils/crx_docker_common.sh
)

if [[ -e "$release" && ! -d "$release/.git" ]] &&
   { [[ ! -d "$release" ]] || [[ -n "$(find "$release" -mindepth 1 -maxdepth 1 ! -name app -print -quit)" ]]; }; then
    printf '%s exists and is not a crxCloudRun Git repository.\n' "$release" >&2
    exit 1
fi
if [[ -d "$release/.git" ]]; then
    # Allow edits to the runtime scripts and other files managed by this release.
    unmanaged=(. ':(exclude)app/')
    for path in "${runtime_paths[@]}" "${tool_paths[@]}" "${template_paths[@]}" "${legacy_paths[@]}" source_revision.txt; do
        unmanaged+=(":(exclude,literal)$path")
    done
    if ! git -C "$release" diff --cached --quiet ||
       [[ -n "$(git -C "$release" status --porcelain --no-renames -- "${unmanaged[@]}")" ]]; then
        printf 'The release repository has staged changes or pending changes outside generated release files.\n' >&2
        exit 1
    fi
    if git -C "$release" show-ref --verify --quiet "refs/heads/$branch"; then
        printf 'Release branch %s already exists. Choose a new dated branch.\n' "$branch" >&2
        exit 1
    fi
fi

stage="$(mktemp -d)"
trap 'rm -r -- "$stage"' EXIT

runtime_repo="$run_root"
if [[ -d "$release/.git" ]]; then runtime_repo="$release"; fi
runtime_files=()
for path in "${runtime_paths[@]}"; do
    file="$runtime_repo/$path"
    if [[ ! -s "$file" ]]; then
        file="$runtime_repo/${path#utils/}"
        if [[ ! -s "$file" ]]; then
            printf 'Missing Docker runtime file: %s/%s\n' "$runtime_repo" "$path" >&2
            exit 1
        fi
    fi
    runtime_files+=("$file")
done

docker build --target server-artifacts --output "type=local,dest=$stage/app" -f "$root/docker/Dockerfile" "$root"
find "$stage/app" -type f -name '*.pdb' -delete
for output in crxServer.dll crxPacker.dll; do test -s "$stage/app/$output"; done

if [[ -d "$release/.git" ]]; then
    git -C "$release" switch -c "$branch"
else
    git init --initial-branch="$branch" "$release"
fi
if [[ -e "$release/app" || -L "$release/app" ]]; then mv -- "$release/app" "$stage/previous-app"; fi
mv -- "$stage/app" "$release/app"
mkdir -p "$release/utils" "$release/tools"
for file in "${runtime_files[@]}"; do
    destination="$release/utils/${file##*/}"
    if [[ ! "$file" -ef "$destination" ]]; then cp -- "$file" "$destination"; fi
done
for path in "${tool_paths[@]}"; do
    if [[ ! "$run_root/$path" -ef "$release/$path" ]]; then
        cp -- "$run_root/$path" "$release/$path"
    fi
done
cp -- "${template_paths[@]/#/$root/docker/cloudrun/}" "$release/"
# Remove generated paths inherited from earlier release layouts.
rm -f -- "${legacy_paths[@]/#/$release/}"
git -C "$root" rev-parse HEAD > "$release/source_revision.txt"
git -C "$release" add --all
git -C "$release" commit -m "Publish crxCloudRun $branch"
printf 'Published locally to %s on branch %s.\n' "$release" "$branch"
