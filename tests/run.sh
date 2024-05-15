#!/bin/sh

set -e

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
GIT_DIR="$(dirname "${SCRIPT_DIR}")"
os="ubuntu"
interactive=0
skip=0

while getopts ":io:r" opt; do
    case "${opt}" in
        "i")
            interactive=1
            skip="$((skip + 1))"
            ;;
        "o")
            os="${OPTARG}"
            skip="$((skip + 2))"
            ;;
        "r")
            rebuild="true"
            skip="$((skip + 1))"
            ;;
        ":")
            echo "${TMPNAME}: -${OPTARG} requires an argument" >&2
            exit 1
            ;;
        *)  ;;
    esac
done

shift "${skip}"

oses="${os}"
fails=""

if [ "${os}" = "all" ]; then
    oses=""
    for config in "${SCRIPT_DIR}/Dockerfile_"*; do
        oses="${oses} ${config##*/Dockerfile_}"
    done
fi

for os in ${oses}; do
    img_tag="privoxy-blocklist-test:${os}"
    dockerfile="${SCRIPT_DIR}/Dockerfile_${os}"
    pytest_cache="pytest_cache_${os}"

    if ! [ -f "${dockerfile}" ]; then
        echo "given OS '${os}' is not supported ('${dockerfile}' missing)"
        exit 1
    fi

    if [ "${rebuild}" = "true" ] || ! docker image ls -q "${img_tag}" | grep -vq '^$' || [ "$(($(date +%s) - $(date -d "$(docker image ls "${img_tag}" --format '{{print .CreatedAt}}' | cut -d' ' -f1,2)" +%s)))" -gt 14400 ]; then
        echo "building docker image for ${os}"
        cd "${GIT_DIR}"
        if docker image ls --format '{{ .Repository }}:{{ .Tag }}' | grep -q "${img_tag}"; then
            docker image rm "${img_tag}" > /dev/null || true
        fi
        if docker volume ls --format '{{ .Name }}' | grep -q "${pytest_cache}"; then
            docker volume rm "${pytest_cache}" > /dev/null || true
        fi
        docker build -q -t "${img_tag}" -f "${dockerfile}" .
        cd -
        echo
    fi

    if [ "${interactive}" -eq 0 ]; then
        echo "running tests on ${os}"
        if ! docker run --rm -w /app -v "${GIT_DIR}:/app" -v "${pytest_cache}:/pytest_cache" "${img_tag}" "${@:-./tests}"; then
            fails="${fails} ${os}"
        fi
    else
        echo "interactive mode on ${os}"
        docker run -ti --rm -w /app -v "${GIT_DIR}:/app" -v "${pytest_cache}:/pytest_cache" --entrypoint /bin/bash "${img_tag}"
    fi
done

if [ -n "${fails}" ]; then
    echo
    echo "Failed: ${fails}"
    exit 1
fi
