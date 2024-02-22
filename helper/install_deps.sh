#!/bin/sh

set -e

exists() {
    if command -v "$1" > /dev/null 2>&1; then
        return 0
    fi
    return 1
}

if exists apk; then
    apk add --no-cache privoxy sed grep bash wget
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
    apt-get install -y privoxy sed grep bash wget
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
# activate debugging of rules & access log
debug 8704
EOF
        fi
        if [ -e /usr/local/share/ca-certificates/privoxy/privoxy-cacert.crt ]; then
            rm /usr/local/share/ca-certificates/privoxy/privoxy-cacert.crt /etc/ssl/certs/privoxy-cacert.pem
        fi
        ln -s /etc/privoxy/CA/cacert.crt /usr/local/share/ca-certificates/privoxy/privoxy-cacert.crt
        update-ca-certificates
        c_rehash
    fi
    exit 0
fi
if exists pacman; then
    pacman -Sy privoxy sed grep bash wget
    if ! grep -q '^debug' /etc/privoxy/config; then
        cat >> /etc/privoxy/config << EOF
# activate debugging of rules & access log
debug 8704
EOF
    fi
    exit 0
fi
if exists opkg; then
    opkg update
    opkg install privoxy bash sed grep wget-ssl
fi
echo "no install command found"
exit 1
