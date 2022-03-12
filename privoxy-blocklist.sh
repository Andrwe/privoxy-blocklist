#!/bin/bash
#
######################################################################
#
#                  Author: Andrwe Lord Weber
#                  Mail: lord-weber-andrwe <at> andrwe <dot> org
#                  Version: 0.3
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

# script config-file
SCRIPTCONF=/etc/conf.d/privoxy-blacklist
# dependencies
DEPENDS=('privoxy' 'sed' 'grep' 'bash' 'wget')

######################################################################
#
#                  No changes needed after this line.
#
######################################################################

function usage() {
    echo "${TMPNAME} is a script to convert AdBlockPlus-lists into Privoxy-lists and install them."
    echo " "
    echo "Options:"
    echo "      -h:    Show this help."
    echo "      -q:    Don't give any output."
    echo "      -v 1:  Enable verbosity 1. Show a little bit more output."
    echo "      -v 2:  Enable verbosity 2. Show a lot more output."
    echo "      -v 3:  Enable verbosity 3. Show all possible output and don't delete temporary files.(For debugging only!!)"
    echo "      -r:    Remove all lists build by this script."
}

if [ ${UID} -ne 0 ]; then
    echo -e "Root privileges needed. Exit.\n\n"
    usage
    exit 1
fi

for dep in "${DEPENDS[@]}"; do
    if ! type -p "${dep}" > /dev/null; then
        echo "The command ${dep} can't be found. Please install the package providing ${dep} and run $0 again. Exit" >&2
        exit 1
    fi
done

if [[ ! -d "$(dirname ${SCRIPTCONF})" ]]; then
    echo "The config directory $(dirname ${SCRIPTCONF}) doesn't exist. Please either adjust the variable SCRIPTCONF in this script or create the directory." >&2
    exit 1
fi

function debug() {
    if [ "${DBG}" -ge "${2}" ]; then
        echo -e "${1}"
    fi
}

function error() {
    printf '\e[1;31m%s\e[0m' "$@" >&2
}

function main() {
    for url in "${URLS[@]}"; do
        debug "Processing ${url} ...\n" 0
        file="${TMPDIR}/$(basename "${url}")"
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

        # convert AdblockPlus list to Privoxy list
        # blacklist of urls
        debug "Creating actionfile for ${list} ..." 1
        echo -e "{ +block{${list}} }" > "${actionfile}"
        sed '/^!.*/d;1,1 d;/^@@.*/d;/\$.*/d;/#/d;s/\./\\./g;s/\?/\\?/g;s/\*/.*/g;s/(/\\(/g;s/)/\\)/g;s/\[/\\[/g;s/\]/\\]/g;s/\^/[\/\&:\?=_]/g;s/^||/\./g;s/^|/^/g;s/|$/\$/g;/|/d' "${file}" >> "${actionfile}"

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
        sed '/^@@.*/!d;s/^@@//g;/\$.*/d;/#/d;s/\./\\./g;s/\?/\\?/g;s/\*/.*/g;s/(/\\(/g;s/)/\\)/g;s/\[/\\[/g;s/\]/\\]/g;s/\^/[\/\&:\?=_]/g;s/^||/\./g;s/^|/^/g;s/|$/\$/g;/|/d' "${file}" >> "${actionfile}"
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

if [[ ! -f "${SCRIPTCONF}" ]]; then
    echo "No config found in ${SCRIPTCONF}. Creating default one and exiting because you might have to adjust it."
    cat > "${SCRIPTCONF}" << EOF
# Config of privoxy-blocklist

# array of URL for AdblockPlus lists
#  for more sources just add it within the round brackets
URLS=("https://easylist-downloads.adblockplus.org/easylistgermany.txt" "https://easylist-downloads.adblockplus.org/easylist.txt")

# config for privoxy initscript providing PRIVOXY_CONF, PRIVOXY_USER and PRIVOXY_GROUP
INIT_CONF="/etc/conf.d/privoxy"

# !! if the config above doesn't exist set these variables here !!
# !! These values will be overwritten by INIT_CONF !!
PRIVOXY_USER="privoxy"
PRIVOXY_GROUP="privoxy"
PRIVOXY_CONF="/etc/privoxy/config"

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
    exit 1
fi

if [[ ! -r "${SCRIPTCONF}" ]]; then
    debug "Can't read ${SCRIPTCONF}. Permission denied." -1
fi

# load script config
# shellcheck disable=SC1090
source "${SCRIPTCONF}"
# load privoxy config
# shellcheck disable=SC1090
if [[ -r "${INIT_CONF}" ]]; then
    source "${INIT_CONF}"
fi

# check whether needed variables are set
if [[ -z "${PRIVOXY_CONF}" ]]; then
    error "\$PRIVOXY_CONF isn't set."
    echo "Please either provide a valid initscript config or set it in ${SCRIPTCONF} ." >&2
    exit 1
fi
if [[ -z "${PRIVOXY_USER}" ]]; then
    error "\$PRIVOXY_USER isn't set"
    echo "Please either provide a valid initscript config or set it in ${SCRIPTCONF} ." >&2
    exit 1
fi
if [[ -z "${PRIVOXY_GROUP}" ]]; then
    error "\$PRIVOXY_GROUP isn't set."
    echo "Please either provide a valid initscript config or set it in ${SCRIPTCONF} ." >&2
    exit 1
fi

# set command to be run on exit
if [ "${DBG}" -le 2 ]; then
    trap 'rm -fr "${TMPDIR}";exit' INT TERM EXIT
fi

# set privoxy config dir
PRIVOXY_DIR="$(dirname "${PRIVOXY_CONF}")"

# file to store current PID
PID_FILE="${TMPDIR}/${TMPNAME}.lock"

# create temporary directory and lock file
install -d -m700 "${TMPDIR}"

# check lock file
if [ -f "${PID_FILE}" ]; then
    if pgrep -P "$(< "${PID_FILE}")"; then
        echo "An Instance of ${TMPNAME} is already running. Exit"
        exit 1
    fi
    debug "Found dead lock file." 0
    rm -f "${PID_FILE}"
    debug "File removed." 0
fi

# safe PID in lock-file
echo $$ > "${PID_FILE}"

VERBOSE=()

# loop for options
while getopts ":hrqv:" opt; do
    case "${opt}" in
        "v")
            DBG="${OPTARG}"
            VERBOSE=("-v")
            ;;
        "q")
            DBG=-1
            ;;
        "r")
            read -rp "Do you really want to remove all build lists?(y/N) " choice
            if [ "${choice}" != "y" ]; then
                exit 0
            fi
            if rm -rf "${PRIVOXY_DIR}/"*.script.{action,filter} \
                && sed '/^actionsfile .*\.script\.action$/d;/^filterfile .*\.script\.filter$/d' -i "${PRIVOXY_CONF}"; then
                echo "Lists removed."
                exit 0
            fi
            echo -e "An error occured while removing the lists.\nPlease have a look into ${PRIVOXY_DIR} whether there are .script.* files and search for *.script.* in ${PRIVOXY_CONF}."
            exit 1
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

debug "URL-List: ${URLS}\nPrivoxy-Configdir: ${PRIVOXY_DIR}\nTemporary directory: ${TMPDIR}" 2
main

# restore default exit command
trap - INT TERM EXIT
if [ "${DBG}" -lt 3 ]; then
    rm -r "${VERBOSE[@]}" "${TMPDIR}"
fi
exit 0

# vim: ts=4 sw=4 et
