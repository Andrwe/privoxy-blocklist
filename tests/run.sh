#!/bin/bash

set -eu

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
GIT_DIR="$(dirname "${SCRIPT_DIR}")"
img_tag="privoxy-blocklist-test"

if [[ "${1:-}" == "rebuild" ]] || ! docker image ls -q "${img_tag}" | grep -vq '^$' || [[ "$(("$( date +%s)" - "$(date -d "$(docker image ls "${img_tag}" --format '{{print .CreatedAt}}' | cut -d' ' -f1,2)" +%s)"))" -gt 1800  ]]; then
    echo "building docker image"
    cd "${GIT_DIR}"
    docker image rm "${img_tag}" > /dev/null || true
    docker volume rm "pytest_cache" > /dev/null || true
    docker build -q -t "${img_tag}" .
    cd -
fi

if [[ "${1:-}" == "rebuild" ]]; then
    shift
fi

docker run --rm -w /app -v "${GIT_DIR}:/app" -v "pytest_cache:/pytest_cache" "${img_tag}" "${@:-./tests}"
