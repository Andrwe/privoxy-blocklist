#!/bin/bash
#
######################################################################
#
#                  Author: Andrwe Lord Weber
#                  Mail: lord-weber-andrwe <at> andrwe <dot> org
#                  Version: <main>
#                  URL: http://andrwe.dyndns.org/doku.php/scripting/bash/privoxy-blocklist
#
##################
#
#                  Sumary:
#                   This script downloads, converts and installs
#                   AdblockPlus lists into Privoxy
#
######################################################################

######################################################################
#
#                 TODO:
#                  - implement:
#                     domain-based filter
#                     id->class combination
#                     class->id combination
#
######################################################################

set -euo pipefail

# dependencies
DEPENDS=('privoxy' 'sed' 'grep' 'bash' 'wget')

######################################################################
#
#                  No changes needed after this line.
#
######################################################################

function usage() {
    echo "${TMPNAME:-this} is a script to convert AdBlockPlus-lists into Privoxy-lists and install them."
    echo " "
    echo "Options:"
    echo "      -h:    Show this help."
    echo "      -c:    Path to script configuration file. (default = OS specific)"
    echo "      -q:    Don't give any output."
    echo "      -v 1:  Enable verbosity 1. Show a little bit more output."
    echo "      -v 2:  Enable verbosity 2. Show a lot more output."
    echo "      -v 3:  Enable verbosity 3. Show all possible output and don't delete temporary files.(For debugging only!!)"
    echo "      -r:    Remove all lists build by this script."
}

function prepare() {
    if [ ${UID} -ne 0 ]; then
        error -e "Root privileges needed. Exit.\n"
        usage
        exit 1
    fi

    for dep in "${DEPENDS[@]}"; do
        if ! type -p "${dep}" > /dev/null; then
            error "The command ${dep} can't be found. Please install the package providing ${dep} and run $0 again. Exit"
            info "To install all dependencies at once you can run 'https://github.com/Andrwe/privoxy-blocklist/blob/main/helper/install_deps.sh'"
            exit 1
        fi
    done

    OS="$(uname)"

    if [ -z "${SCRIPTCONF:-}" ]; then
        # script config-file
        case "${OS}" in
            "Darwin")
                SCRIPTCONF="/usr/local/etc/privoxy-blocklist.conf"
                ;;
            *)
                SCRIPTCONF="/etc/privoxy-blocklist.conf"
                ;;
        esac
        if [ -f "/etc/conf.d/privoxy-blacklist" ]; then
            SCRIPTCONF="/etc/conf.d/privoxy-blacklist"
        fi
    fi

    if [[ ! -d "$(dirname "${SCRIPTCONF}")" ]]; then
        info "creating missing config directory '$(dirname "${SCRIPTCONF}")'"
        install -d -m 755 "$(dirname "${SCRIPTCONF}")"
    fi

    if [[ ! -f "${SCRIPTCONF}" ]]; then
        info "No config found in ${SCRIPTCONF}. Creating default one and exiting because you might have to adjust it."
        cat > "${SCRIPTCONF}" << EOF
# Config of privoxy-blocklist

# array of URL for AdblockPlus lists
#  for more sources just add it within the round brackets
URLS=("https://easylist-downloads.adblockplus.org/easylistgermany.txt" "https://easylist-downloads.adblockplus.org/easylist.txt")

# config for privoxy initscript providing PRIVOXY_CONF, PRIVOXY_USER and PRIVOXY_GROUP
INIT_CONF="/etc/conf.d/privoxy"

# !! set these when config INIT_CONF doesn't exist and default values do not match your system !!
# !! These values will be overwritten by INIT_CONF when exists !!
#PRIVOXY_USER="privoxy"
#PRIVOXY_GROUP="root"
#PRIVOXY_CONF="/etc/privoxy/config"

# name for lock file (default: script name)
TMPNAME="\$(basename "\$(readlink -f "\${0}")")"
# directory for temporary files
TMPDIR="/tmp/\${TMPNAME}"

# Debug-level
#   -1 = quiet
#    0 = normal
#    1 = verbose
#    2 = more verbose (debugging)
#    3 = incredibly loud (function debugging)
DBG=0
EOF
        exit 2
    fi

    if [[ ! -r "${SCRIPTCONF}" ]]; then
        debug "Can't read ${SCRIPTCONF}. Permission denied." -1
    fi

    # load script config
    _dbg="${DBG:-0}"
    # shellcheck disable=SC1090
    source "${SCRIPTCONF}"
    DBG="${_dbg}"
    # load privoxy config
    # shellcheck disable=SC1090
    if [[ -r "${INIT_CONF}" ]]; then
        source "${INIT_CONF}"
    fi

    # set command to be run on exit
    if [ "${DBG}" -gt 2 ]; then
        trap - INT TERM EXIT
    fi

    # check whether needed variables are set
    if [[ -z "${PRIVOXY_CONF:-}" ]]; then
        case "${OS}" in
            "Darwin")
                PRIVOXY_CONF="/usr/local/etc/privoxy/config"
                ;;
            *)
                PRIVOXY_CONF="/etc/privoxy/config"
                ;;
        esac
        PRIVOXY_CONF="/etc/privoxy/config"
        info "\$PRIVOXY_CONF isn't set, falling back to '/etc/privoxy/config'"
    fi
    if [[ -z "${PRIVOXY_USER:-}" ]]; then
        PRIVOXY_USER="privoxy"
        info "\$PRIVOXY_USER isn't set, falling back to 'privoxy'"
    fi
    if [[ -z "${PRIVOXY_GROUP:-}" ]]; then
        PRIVOXY_GROUP="root"
        info "\$PRIVOXY_GROUP isn't set, falling back to 'root'"
    fi

    # set privoxy config dir
    PRIVOXY_DIR="$(dirname "${PRIVOXY_CONF}")"
}

function debug() {
    if [ "${DBG}" -ge "${2}" ]; then
        echo -e "${1}"
    fi
}

function error() {
    printf '\e[1;31m%s\e[0m\n' "$@" >&2
}

function info() {
    printf '\e[1;33m%s\e[0m\n' "$@"
}

# shellcheck disable=SC2317
function main() {
    for url in "${URLS[@]}"; do
        debug "Processing ${url} ...\n" 0
        file="${TMPDIR}/$(basename "${url}")"
        address_file="${TMPDIR}/$(basename "${url}").address"
        address_except_file="${TMPDIR}/$(basename "${url}").address_except"
        url_file="${TMPDIR}/$(basename "${url}").url"
        url_except_file="${TMPDIR}/$(basename "${url}").url_except"
        domain_name_file="${TMPDIR}/$(basename "${url}").domain"
        domain_name_except_file="${TMPDIR}/$(basename "${url}").domain_except"
        regex_file="${TMPDIR}/$(basename "${url}").regex"
        regex_except_file="${TMPDIR}/$(basename "${url}").regex_except"
        actionfile=${file%\.*}.script.action
        filterfile=${file%\.*}.script.filter
        list="$(basename "${file%\.*}")"

        # download list
        debug "Downloading ${url} ..." 0
        wget -t 3 --no-check-certificate -O "${file}" "${url}" > "${TMPDIR}/wget-${url//\//#}.log" 2>&1
        debug "$(cat "${TMPDIR}/wget-${url//\//#}.log")" 2
        debug ".. downloading done." 0
        if ! grep -qE '^.*\[Adblock.*\].*$' "${file}"; then
            echo "The list recieved from ${url} isn't an AdblockPlus list. Skipped"
            continue
        fi

        # remove comments
        sed -i '/^!.*/d;1,1 d' "${file}"
        set +e
        # generate rule based files
        ## domain-name block
        grep -E '^\|\|.*' "${file}" > "${domain_name_file}"
        grep -E '^@@\|\|.*' "${file}" > "${domain_name_except_file}"
        ## exact address block
        grep -E '^\|[^|].*\|' "${file}" > "${address_file}"
        grep -E '^@@\|[^|].*\|' "${file}" > "${address_except_file}"
        ## url block
        grep '^/[^^]' "${file}" > "${url_file}"
        grep '^@@/[^^]' "${file}" > "${url_except_file}"
        ## regex block
        grep '^/^' "${file}" > "${regex_file}"
        grep '^@@/^' "${file}" > "${regex_except_file}"
        set -e

        # convert AdblockPlus list to Privoxy list
        # blacklist of urls
        debug "Creating actionfile for ${list} ..." 1
        echo -e "{ +block{${list}} }" > "${actionfile}"
        sed '/\$.*/d;/#/d;s/\?/\\?/g;s/\*/.*/g;s/(/\\(/g;s/)/\\)/g;s/\[/\\[/g;s/\]/\\]/g;s/\^$//g;s/^||/\./g;s/^|/^/g;s/|$/\$/g;/|/d' "${domain_name_file}" >> "${actionfile}"

        debug "... creating filterfile for ${list} ..." 1
        echo "FILTER: ${list} Tag filter of ${list}" > "${filterfile}"
        # set filter for html elements
        sed '/^#/!d;s/^##//g;s/^#\(.*\)\[.*\]\[.*\]*/s@<([a-zA-Z0-9]+)\\s+.*id=.?\1.*>.*<\/\\1>@@g/g;s/^#\(.*\)/s@<([a-zA-Z0-9]+)\\s+.*id=.?\1.*>.*<\/\\1>@@g/g;s/^\.\(.*\)/s@<([a-zA-Z0-9]+)\\s+.*class=.?\1.*>.*<\/\\1>@@g/g;s/^a\[\(.*\)\]/s@<a.*\1.*>.*<\/a>@@g/g;s/^\([a-zA-Z0-9]*\)\.\(.*\)\[.*\]\[.*\]*/s@<\1.*class=.?\2.*>.*<\/\1>@@g/g;s/^\([a-zA-Z0-9]*\)#\(.*\):.*[\:[^:]]*[^:]*/s@<\1.*id=.?\2.*>.*<\/\1>@@g/g;s/^\([a-zA-Z0-9]*\)#\(.*\)/s@<\1.*id=.?\2.*>.*<\/\1>@@g/g;s/^\[\([a-zA-Z]*\).=\(.*\)\]/s@\1^=\2>@@g/g;s/\^/[\/\&:\?=_]/g;s/\.\([a-zA-Z0-9]\)/\\.\1/g' "${file}" >> "${filterfile}"
        debug "... filterfile created - adding filterfile to actionfile ..." 1
        echo "{ +filter{${list}} }" >> "${actionfile}"
        echo "*" >> "${actionfile}"
        debug "... filterfile added ..." 1

        # create domain based whitelist

        # create domain based blacklist
        #    domains=$(sed '/^#/d;/#/!d;s/,~/,\*/g;s/~/;:\*/g;s/^\([a-zA-Z]\)/;:\1/g' ${file})
        #    [ -n "${domains}" ] && debug "... creating domainbased filterfiles ..." 1
        #    debug "Found Domains: ${domains}." 2
        #    ifs=$IFS
        #    IFS=";:"
        #    for domain in ${domains}
        #    do
        #      dns=$(echo ${domain} | awk -F ',' '{print $1}' | awk -F '#' '{print $1}')
        #      debug "Modifying line: ${domain}" 2
        #      debug "   ... creating filterfile for ${dns} ..." 1
        #      sed '' ${file} > ${file%\.*}-${dns%~}.script.filter
        #      debug "   ... filterfile created ..." 1
        #      debug "   ... adding filterfile for ${dns} to actionfile ..." 1
        #      echo "{ +filter{${list}-${dns}} }" >> ${actionfile}
        #      echo "${dns}" >> ${actionfile}
        #      debug "   ... filterfile added ..." 1
        #    done
        #    IFS=${ifs}
        #    debug "... all domainbased filterfiles created ..." 1

        debug "... creating and adding whitlist for urls ..." 1
        # whitelist of urls
        echo "{ -block }" >> "${actionfile}"
        sed 's/^@@//g;/\$.*/d;/#/d;s/\./\\./g;s/\?/\\?/g;s/\*/.*/g;s/(/\\(/g;s/)/\\)/g;s/\[/\\[/g;s/\]/\\]/g;s/\^/[\/\&:\?=_]/g;s/^||/\./g;s/^|/^/g;s/|$/\$/g;/|/d' "${domain_name_except_file}" >> "${actionfile}"
        debug "... created and added whitelist - creating and adding image handler ..." 1
        # whitelist of image urls
        echo "{ -block +handle-as-image }" >> "${actionfile}"
        sed '/^@@.*/!d;s/^@@//g;/\$.*image.*/!d;s/\$.*image.*//g;/#/d;s/\./\\./g;s/\?/\\?/g;s/\*/.*/g;s/(/\\(/g;s/)/\\)/g;s/\[/\\[/g;s/\]/\\]/g;s/\^/[\/\&:\?=_]/g;s/^||/\./g;s/^|/^/g;s/|$/\$/g;/|/d' "${file}" >> "${actionfile}"
        debug "... created and added image handler ..." 1
        debug "... created actionfile for ${list}." 1

        # install Privoxy actionsfile
        install -o "${PRIVOXY_USER}" -g "${PRIVOXY_GROUP}" "${VERBOSE[@]}" "${actionfile}" "${PRIVOXY_DIR}"
        if ! grep -q "$(basename "${actionfile}")" "${PRIVOXY_CONF}"; then
            debug "\nModifying ${PRIVOXY_CONF} ..." 0
            sed "s/^actionsfile user\.action/actionsfile $(basename "${actionfile}")\nactionsfile user.action/" "${PRIVOXY_CONF}" > "${TMPDIR}/config"
            debug "... modification done.\n" 0
            debug "Installing new config ..." 0
            install -o "${PRIVOXY_USER}" -g "${PRIVOXY_GROUP}" "${VERBOSE[@]}" "${TMPDIR}/config" "${PRIVOXY_CONF}"
            debug "... installation done\n" 0
        fi

        # install Privoxy filterfile
        install -o "${PRIVOXY_USER}" -g "${PRIVOXY_GROUP}" "${VERBOSE[@]}" "${filterfile}" "${PRIVOXY_DIR}"
        if ! grep -q "$(basename "${filterfile}")" "${PRIVOXY_CONF}"; then
            debug "\nModifying ${PRIVOXY_CONF} ..." 0
            sed "s/^\(#*\)filterfile user\.filter/filterfile $(basename "${filterfile}")\n\1filterfile user.filter/" "${PRIVOXY_CONF}" > "${TMPDIR}/config"
            debug "... modification done.\n" 0
            debug "Installing new config ..." 0
            install -o "${PRIVOXY_USER}" -g "${PRIVOXY_GROUP}" "${VERBOSE[@]}" "${TMPDIR}/config" "${PRIVOXY_CONF}"
            debug "... installation done\n" 0
        fi

        debug "... ${url} installed successfully.\n" 0
    done
}

function lock() {
    # file to store current PID
    PID_FILE="${TMPDIR}/${TMPNAME}.lock"

    # create temporary directory and lock file
    install -d -m700 "${TMPDIR}"

    # check lock file
    if [ -f "${PID_FILE}" ]; then
        if pgrep -P "$(< "${PID_FILE}")"; then
            echo "An instance of ${TMPNAME} is already running. Exit"
            exit 1
        fi
        debug "Found dead lock file." 0
        rm -f "${PID_FILE}"
        debug "File removed." 0
    fi

    # safe PID in lock-file
    echo $$ > "${PID_FILE}"
}

# shellcheck disable=SC2317
function remove() {
            read -rp "Do you really want to remove all build lists?(y/N) " choice
            if [ "${choice}" != "y" ]; then
                exit 0
    fi
            if rm -rf "${PRIVOXY_DIR}/"*.script.{action,filter} \
                && sed '/^actionsfile .*\.script\.action$/d;/^filterfile .*\.script\.filter$/d' -i "${PRIVOXY_CONF}"; then
                echo "Lists removed."
                exit 0
    fi
            error "An error occured while removing the lists."
            error "Please have a look into ${PRIVOXY_DIR} whether there are .script.* files and search for *.script.* in ${PRIVOXY_CONF}."
            exit 1
}

VERBOSE=()
method="main"

# loop for options
while getopts ":c:hrqv:" opt; do
    case "${opt}" in
        "c")
            SCRIPTCONF="${OPTARG}"
            ;;
        "v")
            DBG="${OPTARG}"
            VERBOSE=("-v")
            ;;
        "q")
            DBG=-1
            ;;
        "r")
            method="remove"
            ;;
        ":")
            echo "${TMPNAME}: -${OPTARG} requires an argument" >&2
            exit 1
            ;;
        "h" | *)
            usage
            exit 0
            ;;
    esac
done

prepare

trap 'rm -fr "${TMPDIR}";exit' INT TERM EXIT

lock
debug "URL-List: ${URLS}\nPrivoxy-Configdir: ${PRIVOXY_DIR}\nTemporary directory: ${TMPDIR}" 2
"${method}"

# restore default exit command
trap - INT TERM EXIT
if [ "${DBG}" -lt 3 ]; then
    rm -r "${VERBOSE[@]}" "${TMPDIR}"
fi
exit 0

# vim: ts=4 sw=4 et
