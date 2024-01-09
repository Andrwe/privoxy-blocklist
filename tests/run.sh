#!/bin/sh

set -e

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
GIT_DIR="$(dirname "${SCRIPT_DIR}")"
os="ubuntu"

while getopts ":o:r" opt; do
    case "${opt}" in
        "o")
            os="${OPTARG}"
            shift 2
            ;;
        "r")
            rebuild="true"
            shift
            ;;
        ":")
            echo "${TMPNAME}: -${OPTARG} requires an argument" >&2
            exit 1
            ;;
        *)  ;;

    esac
done

img_tag="privoxy-blocklist-test:${os}"
dockerfile="${SCRIPT_DIR}/Dockerfile_${os}"
pytest_cache="pytest_cache_${os}"

if ! [ -f "${dockerfile}" ]; then
    echo "given OS '${os}' is not supported ('${dockerfile}' missing)"
    exit 1
fi

if [ "${rebuild}" = "true" ] || ! docker image ls -q "${img_tag}" | grep -vq '^$' || [ "$(($(date +%s) - $(date -d "$(docker image ls "${img_tag}" --format '{{print .CreatedAt}}' | cut -d' ' -f1,2)" +%s)))" -gt 14400 ]; then
    echo "building docker image"
    cd "${GIT_DIR}"
    if docker image ls --format '{{ .Repository }}:{{ .Tag }}' | grep -q "${img_tag}"; then
        docker image rm "${img_tag}" > /dev/null || true
    fi
    if docker volume ls --format '{{ .Name }}' | grep -q "${pytest_cache}"; then
        docker volume rm "${pytest_cache}" > /dev/null || true
    fi
    docker build -q -t "${img_tag}" -f "${dockerfile}" .
    cd -
fi

docker run --rm -w /app -v "${GIT_DIR}:/app" -v "${pytest_cache}:/pytest_cache" "${img_tag}" "${@:-./tests}"
