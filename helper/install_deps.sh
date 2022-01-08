#!/bin/sh

set -e

exists() {
    if command -v "$1" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

if exists apk;then
    apk add --no-cache privoxy sed grep bash wget
    exit 0
fi
if exists apt-get; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq -y
    apt-get install -y privoxy sed grep bash wget
    exit 0
fi
if exists pacman; then
    pacman -Sy privoxy sed grep bash wget
    exit 0
fi
echo "no install command found"
exit 1
