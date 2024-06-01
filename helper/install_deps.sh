#!/bin/sh

set -e

SCRIPTDIR="$(dirname "$(readlink -f "$0")")"

exists() {
    if command -v "$1" > /dev/null 2>&1; then
        return 0
    fi
    return 1
}

pip_install() {
    python3 -m venv /.venv
    # shellcheck disable=SC1091
    . /.venv/bin/activate
    pip install --no-cache-dir -r "${SCRIPTDIR}/../tests/requirements.txt"
}

if exists apk; then
    apk add --no-cache \
        bash \
        grep \
        privoxy \
        sed \
        wget

    # prepare system in Github Pipeline
    if [ -n "$CI" ]; then
        apk add --no-cache --quiet \
            build-base \
            linux-headers \
            py3-pip \
            python3-dev
        pip_install
        # prepare configuration files
        for f in /etc/privoxy/*.new; do
            cp -p "$f" "${f%.*}"
        done
        adduser -h /home/ci_test_user -s /bin/bash -D ci_test_user
    fi
    if ! grep -q '^debug' /etc/privoxy/config; then
        cat >> /etc/privoxy/config << EOF
# activate debugging of rules & access log
debug 8704
EOF
    fi
    exit 0
fi
if exists apt-get; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq -y
    apt-get install --no-install-recommends -y \
        bash \
        grep \
        privoxy \
        sed \
        wget

    # prepare system in Github Pipeline
    if [ -n "$CI" ]; then
        apt-get install --no-install-recommends --yes \
            apparmor \
            curl \
            build-essential \
            python3-dev \
            python3-pip \
            python3-venv
        pip_install
        systemctl disable --now privoxy || true
        useradd -s /bin/bash ci_test_user
    fi
    if [ -n "${HTTPS_SUPPORT:-}" ]; then
        # prepare HTTPS inspection
        mkdir -p /etc/privoxy/CA/certs /usr/local/share/ca-certificates/privoxy
        openssl req -new -x509 -extensions v3_ca -keyout /etc/privoxy/CA/cakey.pem -out /etc/privoxy/CA/cacert.crt -days 3650 -noenc -batch
        chown -R privoxy /etc/privoxy/CA
        if ! grep -q '^{+https-inspection}' /etc/privoxy/user.action; then
            cat >> /etc/privoxy/user.action << EOF
{+https-inspection}
.
EOF
        fi
        if ! grep -q '^ca-directory' /etc/privoxy/config; then
            cat >> /etc/privoxy/config << EOF
ca-directory /etc/privoxy/CA
certificate-directory /var/lib/privoxy/certs
trusted-cas-file /etc/ssl/certs/ca-certificates.crt
ca-cert-file cacert.crt
ca-key-file cakey.pem
EOF
        fi
        if [ -e /usr/local/share/ca-certificates/privoxy/privoxy-cacert.crt ]; then
            rm /usr/local/share/ca-certificates/privoxy/privoxy-cacert.crt /etc/ssl/certs/privoxy-cacert.pem
        fi
        ln -s /etc/privoxy/CA/cacert.crt /usr/local/share/ca-certificates/privoxy/privoxy-cacert.crt
        update-ca-certificates
        c_rehash
    fi
    if ! grep -q '^debug' /etc/privoxy/config; then
        cat >> /etc/privoxy/config << EOF
# activate debugging of rules & access log
debug 8704
EOF
    fi
    exit 0
fi
if exists pacman; then
    pacman -Sy \
        bash \
        grep \
        privoxy \
        sed \
        wget
    if ! grep -q '^debug' /etc/privoxy/config; then
        cat >> /etc/privoxy/config << EOF
# activate debugging of rules & access log
debug 8704
EOF
    fi
    exit 0
fi
if exists opkg; then
    if ! [ -e "/var/lock" ]; then
        mkdir /var/lock/
    fi
    if ! [ -e "/var/run" ]; then
        mkdir /var/run/
    fi
    opkg update
    opkg install \
        bash \
        grep \
        privoxy \
        sed \
        wget-ssl

    # prepare system in Github Pipeline
    if [ -n "$CI" ]; then
        opkg install \
            curl \
            gcc \
            make \
            python3 \
            python3-pip \
            python3-dev \
            python3-venv \
            shadow-useradd
        pip_install
        /etc/rc.d/K10privoxy stop || true
        echo "        list    listen_address  '127.0.0.1:8118'" >> /etc/config/privoxy
        echo "        list    permit_access           '127.0.0.0/24'" >> /etc/config/privoxy
        useradd -s /bin/bash ci_test_user
    fi
    # openwrt version not compiled with HTTPS support, thus just keeping for future reference
    if [ -n "${HTTPS_SUPPORT:-}" ]; then
        # prepare HTTPS inspection
        opkg install openssl-util
        privoxy_cert_dir="/etc/config/privoxy_certs"
        cert_path="${privoxy_cert_dir}/privoxy_cacert.crt"
        mkdir -p "${privoxy_cert_dir}"
        openssl req -new -x509 -extensions v3_ca -keyout "${privoxy_cert_dir}/cakey.pem" -out "${cert_path}" -days 3650 -noenc -batch
        cert_hash="$(openssl x509 -hash -noout -in "${cert_path}").0"
        ln -s "${cert_path}" "/etc/ssl/certs/privoxy_cacert.crt"
        ln -s "/etc/ssl/certs/privoxy_cacert.crt" "/etc/ssl/certs/${cert_hash}"
        chown -R privoxy "${privoxy_cert_dir}"
        if ! grep -q '^{+https-inspection}' /etc/config/privoxy_https.action; then
            cat >> /etc/config/privoxy_https.action << EOF
{+https-inspection}
.
EOF
        fi
        if ! grep -q '^\s*option\s*ca-directory' /etc/config/privoxy; then
            cat >> /etc/config/privoxy << EOF
        option  ca-directory            '${privoxy_cert_dir}'
        option  certificate-directory   '${privoxy_cert_dir}'
        option  trusted-cas-file        '/etc/ssl/certs/ca-certificates.crt'
        option  ca-cert-file            'privoxy_cacert.crt'
        option  ca-key-file             'cakey.pem'
        list    actionsfile             '/etc/config/privoxy_https.action'
EOF
        fi
    fi
    if ! grep -q '^debug' /etc/config/privoxy; then
        cat >> /etc/config/privoxy << EOF
        option  debug             '8704'
EOF
    fi
    exit 0
fi
echo "no install command found"
exit 1
