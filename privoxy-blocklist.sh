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

# types of content filters
#   used in conftest.py, thus keep structure
FILTERTYPES=(
    "attribute_global_name"
    "attribute_global_exact"
    "attribute_global_contain"
    "attribute_global_startswith"
    "attribute_global_endswith"
    "class_global"
    "id_global"
)

######################################################################
#
#                  No changes needed after this line.
#
######################################################################

function usage() {
    get_config_path
    echo "${TMPNAME:-This} is a script to convert AdBlockPlus-lists into Privoxy-lists and install them."
    echo " "
    echo "Options:"
    echo "      -h:         Show this help."
    echo "      -c:         Path to script configuration file. (default = ${SCRIPTCONF} - OS specific)"
    echo "      -f filter:  only activate given content filter, can be used multiple times. (default: empty, content-filter disabled)"
    echo "                  Supported values: ${FILTERTYPES[*]}"
    echo "      -q:         Don't give any output."
    echo "      -v 1:       Enable verbosity 1. Show a little bit more output."
    echo "      -v 2:       Enable verbosity 2. Show a lot more output."
    echo "      -v 3:       Enable verbosity 3. Show all possible output and don't delete temporary files.(For debugging only!!)"
    echo "      -V:         Show version."
    echo "      -r:         Remove all lists build by this script."
}

function get_config_path() {
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
}

function prepare() {
    if [ ${UID} -ne 0 ]; then
        error "Root privileges needed. Exit."
        usage
        exit 1
    fi

    for dep in "${DEPENDS[@]}"; do
        if ! type -p "${dep}" > /dev/null; then
            error "The command ${dep} can't be found. Please install the package providing ${dep} and run $0 again. Exit"
            info "To install all dependencies at once you can run 'https://raw.githubusercontent.com/Andrwe/privoxy-blocklist/main/helper/install_deps.sh'"
            exit 1
        fi
    done

    if [ -z "${SCRIPTCONF:-}" ]; then
        get_config_path
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
URLS=(
  "https://easylist-downloads.adblockplus.org/easylistgermany.txt"
  "https://easylist-downloads.adblockplus.org/easylist.txt"
)

# array of content filters to convert
#   for supported values check: $0 -h
#   empty by default to deactivate as content filters slowdown privoxy a lot
FILTERS=()

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
        debug -1 "Can't read ${SCRIPTCONF}. Permission denied."
    fi

    # shellcheck disable=SC1090
    source "${SCRIPTCONF}"
    if [ -n "${OPT_DBG:-}" ]; then
        DBG="${OPT_DBG}"
    fi
    if [ -n "${OPT_FILTERS[*]}" ]; then
        FILTERS=("${OPT_FILTERS[@]}")
    fi
    debug 2 "Content filters: ${OPT_FILTERS[*]:-disabled}"

    # load privoxy config
    # shellcheck disable=SC1090
    if [[ -r "${INIT_CONF:-no-init-conf}" ]]; then
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
        info "\$PRIVOXY_CONF isn't set, falling back to '${PRIVOXY_CONF}'"
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
    local expected_level="${1}"
    shift 1
    if [ "${DBG}" -ge "${expected_level}" ]; then
        if [ "${expected_level}" -eq 0 ]; then
            info "${@}"
        else
            printf '%s\n' "${@}"
        fi
    fi
}

function error() {
    printf '\e[1;31m%s\e[0m\n' "$@" >&2
}

function info() {
    printf '\e[1;33m%s\e[0m\n' "$@"
}

# shellcheck disable=SC2317  # function is called in case of FILTERS not empty
function filter_active() {
    grep -qxF "$1" <(printf '%s\n' "${FILTERS[@]}")
}

# shellcheck disable=SC2317
function main() {
    for url in "${URLS[@]}"; do
        debug 0 "Processing ${url} ..."
        file="${TMPDIR}/$(basename "${url}")"
        address_file="${file}.address"
        address_except_file="${file}.address_except"
        url_file="${file}.url"
        url_except_file="${file}.url_except"
        domain_name_file="${file}.domain"
        domain_name_except_file="${file}.domain_except"
        regex_file="${file}.regex"
        regex_except_file="${file}.regex_except"
        html_file="${file}.html"
        html_except_file="${file}.html_except"
        actionfile=${file%\.*}.script.action
        filterfile=${file%\.*}.script.filter
        list="$(basename "${file%\.*}")"

        # download list
        debug 0 "Downloading ${url} ..."
        wget -t 3 --no-check-certificate -O "${file}" "${url}" > "${TMPDIR}/wget-${url//\//#}.log" 2>&1
        debug 2 "$(cat "${TMPDIR}/wget-${url//\//#}.log")"
        debug 0 ".. downloading done."
        if ! grep -qE '^.*\[Adblock.*\].*$' "${file}"; then
            info "The list recieved from ${url} does not contain AdblockPlus list header. Try to process anyway."
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
        ## html element block
        grep -E '^.*##.+' "${file}" > "${html_file}"
        grep -E '^.*#@#.+' "${file}" > "${html_except_file}"
        set -e

        # convert AdblockPlus list to Privoxy list
        # blacklist of urls
        debug 1 "Creating actionfile for ${list} ..."
        echo "{ +block{${list}} }" > "${actionfile}"
        sed '
        # skip domains with additional filter definition
        /\$.*/d
        # skip domains with HTML filter
        /#/d
        # replace characters to match Privoxy domain syntax
        s/\?/\\?/g;s/\*/.*/g;s/(/\\(/g;s/)/\\)/g;s/\[/\\[/g;s/\]/\\]/g
        # replace marking seperator of Adblock
        s/\^$//g
        # replace domain matcher
        s/^||/\./g
        ' "${domain_name_file}" >> "${actionfile}"
        sed '
        # skip domains with additional filter definition
        /\$.*/d
        # skip domains with HTML filter
        /#/d
        # replace characters to match Privoxy domain syntax
        s/\?/\\?/g;s/\*/.*/g;s/(/\\(/g;s/)/\\)/g;s/\[/\\[/g;s/\]/\\]/g
        # replace marking seperator of Adblock
        s/\^$//g
        # handle exact domain matching
        s/^|\([^|][^|]*\)|/^\1\$/g;s/|$/\$/g
        ' "${address_file}" >> "${actionfile}"

        echo > "${filterfile}"
        if [ -n "${FILTERS[*]}" ]; then
            debug 1 "... creating filterfile for ${list} ..."
            if filter_active "class_global"; then
                debug 1 "... processing global 'class'-matches ..."
                (
                    # allow handling of left-over lines from last while-loop-run
                    shopt -s lastpipe
                    echo "FILTER: ${list}_class_global Tag filter of ${list}"
                    lines=()
                    # using while-loop as privoxy cannot handle more than 2000 or-connected strings within one regex
                    sed -e '
                        # only process gloabl class matches
                        /^##\..*/!d
                        # remove all combinations with attribute matching
                        /^##\..*\[.*/d
                        # remove all matches with combinators
                        /^##\..*[>+~ ].*/d
                        # cleanup
                        s/^##\.//g
                        # prepare regex merging
                        s/$/|/
                    ' "${html_file}" | while read -r line; do
                        # number of matches within one rule impacts runtime of each request to modify the content
                        if [ "${#lines[@]}" -lt 1000 ]; then
                            lines+=("$line")
                            continue
                        fi
                        # complexity of regex impacts runtime of each request to modify the content
                        # using removal of whole HTML tag as multiple matches with different classes in same element are not possible
                        # printf to inject both quoting characters " and '
                        printf 's@<([a-zA-Z0-9]+)\\s+.*class=[%s][^%s]*(' "\"'" "\"'"
                        # using tr to merge lines because sed-based approachs takes up to 6 MB RAM and >10 seconds during testing
                        printf '%s\n' "${lines[@]}" | sed '$ s/|//' | tr -d '\n'
                        # printf to inject both quoting characters " and '
                        printf ')[^%s]*[%s].*>.*<\/\\1[^>]*>@@g\n' "\"'" "\"'"
                        lines=()
                    done
                    # process last chunk with less than 1000 entries
                    if [ "${#lines[@]}" -gt 0 ]; then
                        printf 's@<([a-zA-Z0-9]+)\\s+.*class=[%s][^%s]*(' "\"'" "\"'"
                        printf '%s\n' "${lines[@]}" | sed '$ s/|//' | tr -d '\n'
                        printf ')[^%s]*[%s].*>.*<\/\\1[^>]*>@@g\n' "\"'" "\"'"
                    fi
                    shopt -u lastpipe
                ) >> "${filterfile}"

                debug 1 "... registering ${list}_class_global in actionfile ..."
                (
                    echo "{ +filter{${list}_class_global} }"
                    echo "/"
                ) >> "${actionfile}"
                debug 1 "... registered ..."
                # FIXME: add class handling with domains
                # FIXME: add class handling with combinators
                # FIXME: add class with defined HTML tag ?
                # FIXME: add class with cascading
            fi

            if filter_active "id_global"; then
                debug 1 "... processing global 'id'-matches ..."
                echo "FILTER: ${list}_id_global Tag filter of ${list}" >> "${filterfile}"
                (
                    # allow handling of left-over lines from last while-loop-run
                    shopt -s lastpipe
                    lines=()
                    # using while-loop as privoxy cannot handle more than 2000 or-connected strings within one regex
                    sed -e '
                        # only process gloabl id-only matches
                        /^###.*/!d
                        # remove all matches with combinators
                        /^###.*[>+~ ].*/d
                        # cleanup
                        s/^###//g
                        # prepare regex merging
                        s/$/|/
                    ' "${html_file}" | while read -r line; do
                        # number of matches within one rule impacts runtime of each request to modify the content
                        if [ "${#lines[@]}" -lt 1000 ]; then
                            lines+=("$line")
                            continue
                        fi
                        # complexity of regex impacts runtime of each request to modify the content
                        # using removal of whole HTML tag as multiple matches with different classes in same element are not possible
                        # printf to inject both quoting characters " and '
                        printf 's@<([a-zA-Z0-9]+)\\s+.*id=[%s](' "\"'"
                        # using tr to merge lines because sed-based approachs takes up to 6 MB RAM and >10 seconds during testing
                        printf '%s\n' "${lines[@]}" | sed '$ s/|//' | tr -d '\n'
                        # printf to inject both quoting characters " and '
                        printf ')[%s].*>.*<\/\\1[^>]*>@@g\n' "\"'"
                        lines=()
                    done
                    # process last chunk with less than 1000 entries
                    if [ "${#lines[@]}" -gt 0 ]; then
                        printf 's@<([a-zA-Z0-9]+)\\s+.*id=[%s](' "\"'"
                        printf '%s\n' "${lines[@]}" | sed '$ s/|//' | tr -d '\n'
                        printf ')[%s].*>.*<\/\\1[^>]*>@@g\n' "\"'"
                    fi
                    shopt -u lastpipe
                ) >> "${filterfile}"

                debug 1 "... registering ${list}_id_global in actionfile ..."
                (
                    echo "{ +filter{${list}_id_global} }"
                    echo "/"
                ) >> "${actionfile}"
                debug 1 "... registered ..."
                # FIXME: add id handling with domains
                # FIXME: add id handling with combinators
                # FIXME: add id with cascading
            fi

            debug 1 "... processing 'attribute'-matches with no HTML tag ..."
            (
                shopt -s lastpipe

                if filter_active "attribute_global_name"; then
                    # allow handling of left-over lines from last while-loop-run
                    echo "FILTER: ${list}_attribute_global_name Tag filter of ${list}"
                    lines=()
                    # using while-loop as privoxy cannot handle more than 2000 or-connected strings within one regex
                    sed -e '
                        # only process gloabl classes
                        /^##\[[^=][^=]*$/!d
                        # remove all matches with combinators
                        /^##.*[>+~ ].*/d
                        # cleanup
                        s/^##//g
                        # convert attribute name-only matches
                        s/^\[\([^=][^=]*\)\]/\1/g
                        # convert dots
                        s/\.\([^\.]\)/\\.\1/g
                        s/$/|/
                    ' "${html_file}" | sort -u | while read -r line; do
                        # number of matches within one rule impacts runtime of each request to modify the content
                        if [ "${#lines[@]}" -lt 1000 ]; then
                            lines+=("$line")
                            continue
                        fi
                        # complexity of regex impacts runtime of each request to modify the content
                        # using removal of whole HTML tag as multiple matches with different classes in same element are not possible
                        # printf to inject both quoting characters " and '
                        printf 's@<([a-zA-Z0-9]+)\\s+.*('
                        # using tr to merge lines because sed-based approachs takes up to 6 MB RAM and >10 seconds during testing
                        printf '%s\n' "${lines[@]}" | sed '$ s/|//' | tr -d '\n'
                        # printf to inject both quoting characters " and '
                        printf ').*>.*<\/\\1[^>]*>@@g\n'
                        lines=()
                    done
                    # process last chunk with less than 1000 entries
                    if [ "${#lines[@]}" -gt 0 ]; then
                        printf 's@<([a-zA-Z0-9]+)\\s+.*('
                        printf '%s\n' "${lines[@]}" | sed '$ s/|//' | tr -d '\n'
                        printf ').*>.*<\/\\1[^>]*>@@g\n'
                    fi
                fi

                if filter_active "attribute_global_exact"; then
                    echo "FILTER: ${list}_attribute_global_exact Tag filter of ${list}"
                    lines=()
                    # using while-loop as privoxy cannot handle more than 2000 or-connected strings within one regex
                    sed -e '
                        # only process gloabl classes
                        /^##\[[^=^*][^=^*]*=.*$/!d
                        # remove all matches with combinators
                        /^##.*[>+~ ].*/d
                        # cleanup
                        s/^##//g
                        # convert attribute name-only matches
                        s/^\[\([^=][^=]*\)=\(.*\)\]/\1=\2/g
                        # convert dots
                        s/\.\([^\.]\)/\\.\1/g
                        s/$/|/
                    ' "${html_file}" | sort -u | while read -r line; do
                        # number of matches within one rule impacts runtime of each request to modify the content
                        if [ "${#lines[@]}" -lt 1000 ]; then
                            lines+=("$line")
                            continue
                        fi
                        # complexity of regex impacts runtime of each request to modify the content
                        # using removal of whole HTML tag as multiple matches with different classes in same element are not possible
                        # printf to inject both quoting characters " and '
                        printf 's@<([a-zA-Z0-9]+)\\s+.*('
                        # using tr to merge lines because sed-based approachs takes up to 6 MB RAM and >10 seconds during testing
                        printf '%s\n' "${lines[@]}" | sed '$ s/|//' | tr -d '\n'
                        # printf to inject both quoting characters " and '
                        printf ').*>.*<\/\\1[^>]*>@@g\n'
                        lines=()
                    done
                    # process last chunk with less than 1000 entries
                    if [ "${#lines[@]}" -gt 0 ]; then
                        printf 's@<([a-zA-Z0-9]+)\\s+.*('
                        printf '%s\n' "${lines[@]}" | sed '$ s/|//' | tr -d '\n'
                        printf ').*>.*<\/\\1[^>]*>@@g\n'
                    fi
                fi

                if filter_active "attribute_global_contain"; then
                    echo "FILTER: ${list}_attribute_global_contain Tag filter of ${list}"
                    lines=()
                    # using while-loop as privoxy cannot handle more than 2000 or-connected strings within one regex
                    sed -e '
                        # only process gloabl classes
                        /^##\[[^*][^*]*\*=.*$/!d
                        # remove all matches with combinators
                        /^##.*[>+~ ].*/d
                        # cleanup
                        s/^##//g
                        # convert dots
                        s/\.\([^\.]\)/\\.\1/g
                        # convert attribute based filter with contain match
                        s/^\[\([^*][^*]*\)\*=\(["'"'"']*\)\([^"][^"]*\)"*\(["'"'"']*\)\]/\1=\2.*\3.*\4/g
                        s/$/|/
                    ' "${html_file}" | sort -u | while read -r line; do
                        # number of matches within one rule impacts runtime of each request to modify the content
                        if [ "${#lines[@]}" -lt 1000 ]; then
                            lines+=("$line")
                            continue
                        fi
                        # complexity of regex impacts runtime of each request to modify the content
                        # using removal of whole HTML tag as multiple matches with different classes in same element are not possible
                        # printf to inject both quoting characters " and '
                        printf 's@<([a-zA-Z0-9]+)\\s+.*('
                        # using tr to merge lines because sed-based approachs takes up to 6 MB RAM and >10 seconds during testing
                        printf '%s\n' "${lines[@]}" | sed '$ s/|//' | tr -d '\n'
                        # printf to inject both quoting characters " and '
                        printf ').*>.*<\/\\1[^>]*>@@g\n'
                        lines=()
                    done
                    # process last chunk with less than 1000 entries
                    if [ "${#lines[@]}" -gt 0 ]; then
                        printf 's@<([a-zA-Z0-9]+)\\s+.*('
                        printf '%s\n' "${lines[@]}" | sed '$ s/|//' | tr -d '\n'
                        printf ').*>.*<\/\\1[^>]*>@@g\n'
                    fi
                fi

                if filter_active "attribute_global_startswith"; then
                    echo "FILTER: ${list}_attribute_global_startswith Tag filter of ${list}"
                    lines=()
                    # using while-loop as privoxy cannot handle more than 2000 or-connected strings within one regex
                    sed -e '
                        # only process gloabl classes
                        /^##\[[^=^][^=^]*\^=.*$/!d
                        # remove all matches with combinators
                        /^##.*[>+~ ].*/d
                        # cleanup
                        s/^##//g
                        # convert dots
                        s/\.\([^\.]\)/\\.\1/g
                        # convert attribute based filter with startwith match
                        s/^\[\([^^][^^]*\)^=\(["'"'"']*\)\(.*[^"'"'"']\)\(["'"'"']*\)\]/\1=\2\3.*\4/g
                        s/$/|/
                    ' "${html_file}" | sort -u | while read -r line; do
                        # number of matches within one rule impacts runtime of each request to modify the content
                        if [ "${#lines[@]}" -lt 1000 ]; then
                            lines+=("$line")
                            continue
                        fi
                        # complexity of regex impacts runtime of each request to modify the content
                        # using removal of whole HTML tag as multiple matches with different classes in same element are not possible
                        # printf to inject both quoting characters " and '
                        printf 's@<([a-zA-Z0-9]+)\\s+.*('
                        # using tr to merge lines because sed-based approachs takes up to 6 MB RAM and >10 seconds during testing
                        printf '%s\n' "${lines[@]}" | sed '$ s/|//' | tr -d '\n'
                        # printf to inject both quoting characters " and '
                        printf ').*>.*<\/\\1[^>]*>@@g\n'
                        lines=()
                    done
                    # process last chunk with less than 1000 entries
                    if [ "${#lines[@]}" -gt 0 ]; then
                        printf 's@<([a-zA-Z0-9]+)\\s+.*('
                        printf '%s\n' "${lines[@]}" | sed '$ s/|//' | tr -d '\n'
                        printf ').*>.*<\/\\1[^>]*>@@g\n'
                    fi
                fi

                if filter_active "attribute_global_endswith"; then
                    echo "FILTER: ${list}_attribute_global_endswith Tag filter of ${list}"
                    lines=()
                    # using while-loop as privoxy cannot handle more than 2000 or-connected strings within one regex
                    sed -e '
                        # only process gloabl classes
                        /^##\[[^$][^=$]*\$=.*$/!d
                        # remove all matches with combinators
                        /^##.*[>+~ ].*/d
                        # cleanup
                        s/^##//g
                        # convert dots
                        s/\.\([^\.]\)/\\.\1/g
                        # convert attribute based filter with endswith match
                        s/^\[\([^\$][^\$]*\)\$=\(["'"'"']*\)\(.*[^"'"'"']\)\(["'"'"']*\)\]/\1=\2.*\3\4/g
                        s/$/|/
                    ' "${html_file}" | sort -u | while read -r line; do
                        # number of matches within one rule impacts runtime of each request to modify the content
                        if [ "${#lines[@]}" -lt 1000 ]; then
                            lines+=("$line")
                            continue
                        fi
                        # complexity of regex impacts runtime of each request to modify the content
                        # using removal of whole HTML tag as multiple matches with different classes in same element are not possible
                        # printf to inject both quoting characters " and '
                        printf 's@<([a-zA-Z0-9]+)\\s+.*('
                        # using tr to merge lines because sed-based approachs takes up to 6 MB RAM and >10 seconds during testing
                        printf '%s\n' "${lines[@]}" | sed '$ s/|//' | tr -d '\n'
                        # printf to inject both quoting characters " and '
                        printf ').*>.*<\/\\1[^>]*>@@g\n'
                        lines=()
                    done
                    # process last chunk with less than 1000 entries
                    if [ "${#lines[@]}" -gt 0 ]; then
                        printf 's@<([a-zA-Z0-9]+)\\s+.*('
                        printf '%s\n' "${lines[@]}" | sed '$ s/|//' | tr -d '\n'
                        printf ').*>.*<\/\\1[^>]*>@@g\n'
                    fi
                fi
                shopt -u lastpipe
            ) >> "${filterfile}"

            debug 1 "... registering ${list}_attribute filters in actionfile ..."
            (
                if filter_active "attribute_global_name"; then
                    echo "{ +filter{${list}_attribute_global_name} }"
                    echo "/"
                fi
                if filter_active "attribute_global_exact"; then
                    echo "{ +filter{${list}_attribute_global_exact} }"
                    echo "/"
                fi
                if filter_active "attribute_global_contain"; then
                    echo "{ +filter{${list}_attribute_global_contain} }"
                    echo "/"
                fi
                if filter_active "attribute_global_startswith"; then
                    echo "{ +filter{${list}_attribute_global_startswith} }"
                    echo "/"
                fi
                if filter_active "attribute_global_endswith"; then
                    echo "{ +filter{${list}_attribute_global_endswith} }"
                    echo "/"
                fi
            ) >> "${actionfile}"
            debug 1 "... registered ..."

            # FIXME: add attribute handling with domains
            # FIXME: add attribute handling with combinators
            # FIXME: add combination of classes and attributes: ##.OUTBRAIN[data-widget-id^="FMS_REELD_"]
        fi

        # create domain based whitelist

        # create domain based blacklist
        #    domains=$(sed '/^#/d;/#/!d;s/,~/,\*/g;s/~/;:\*/g;s/^\([a-zA-Z]\)/;:\1/g' ${file})
        #    [ -n "${domains}" ] && debug 1 "... creating domainbased filterfiles ..."
        #    debug 2 "Found Domains: ${domains}."
        #    ifs=$IFS
        #    IFS=";:"
        #    for domain in ${domains}
        #    do
        #      dns=$(echo ${domain} | awk -F ',' '{print $1}' | awk -F '#' '{print $1}')
        #      debug 2 "Modifying line: ${domain}"
        #      debug 1 "   ... creating filterfile for ${dns} ..."
        #      sed '' ${file} > ${file%\.*}-${dns%~}.script.filter
        #      debug 1 "   ... filterfile created ..."
        #      debug 1 "   ... adding filterfile for ${dns} to actionfile ..."
        #      echo "{ +filter{${list}-${dns}} }" >> ${actionfile}
        #      echo "${dns}" >> ${actionfile}
        #      debug 1 "   ... filterfile added ..."
        #    done
        #    IFS=${ifs}
        #    debug 1 "... all domainbased filterfiles created ..."

        debug 1 "... creating and adding whitlist for urls ..."
        # whitelist of urls
        echo "{ -block }" >> "${actionfile}"
        sed 's/^@@//g;/\$.*/d;/#/d;s/\./\\./g;s/\?/\\?/g;s/\*/.*/g;s/(/\\(/g;s/)/\\)/g;s/\[/\\[/g;s/\]/\\]/g;s/\^/[\/\&:\?=_]/g;s/^||/\./g;s/^|/^/g;s/|$/\$/g;/|/d' "${domain_name_except_file}" >> "${actionfile}"
        debug 1 "... created and added whitelist - creating and adding image handler ..."
        # whitelist of image urls
        echo "{ -block +handle-as-image }" >> "${actionfile}"
        sed '/^@@.*/!d;s/^@@//g;/\$.*image.*/!d;s/\$.*image.*//g;/#/d;s/\./\\./g;s/\?/\\?/g;s/\*/.*/g;s/(/\\(/g;s/)/\\)/g;s/\[/\\[/g;s/\]/\\]/g;s/\^/[\/\&:\?=_]/g;s/^||/\./g;s/^|/^/g;s/|$/\$/g;/|/d' "${file}" >> "${actionfile}"
        debug 1 "... created and added image handler ..."
        debug 1 "... created actionfile for ${list}."

        # install Privoxy actionsfile
        install -o "${PRIVOXY_USER}" -g "${PRIVOXY_GROUP}" "${VERBOSE[@]}" "${actionfile}" "${PRIVOXY_DIR}"
        if ! grep -q "$(basename "${actionfile}")" "${PRIVOXY_CONF}"; then
            debug 0 "Modifying ${PRIVOXY_CONF} ..."
            sed "s/^actionsfile user\.action/actionsfile $(basename "${actionfile}")\nactionsfile user.action/" "${PRIVOXY_CONF}" > "${TMPDIR}/config"
            debug 0 "... modification done."
            debug 0 "Installing new config ..."
            install -o "${PRIVOXY_USER}" -g "${PRIVOXY_GROUP}" "${VERBOSE[@]}" "${TMPDIR}/config" "${PRIVOXY_CONF}"
            debug 0 "... installation done"
        fi

        # install Privoxy filterfile
        install -o "${PRIVOXY_USER}" -g "${PRIVOXY_GROUP}" "${VERBOSE[@]}" "${filterfile}" "${PRIVOXY_DIR}"
        if ! grep -q "$(basename "${filterfile}")" "${PRIVOXY_CONF}"; then
            debug 0 "Modifying ${PRIVOXY_CONF} ..."
            sed "s/^\(#*\)filterfile user\.filter/filterfile $(basename "${filterfile}")\n\1filterfile user.filter/" "${PRIVOXY_CONF}" > "${TMPDIR}/config"
            debug 0 "... modification done."
            debug 0 "Installing new config ..."
            install -o "${PRIVOXY_USER}" -g "${PRIVOXY_GROUP}" "${VERBOSE[@]}" "${TMPDIR}/config" "${PRIVOXY_CONF}"
            debug 0 "... installation done"
        fi

        debug 0 "... ${url} installed successfully."
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
        debug 0 "Found dead lock file."
        rm -f "${PID_FILE}"
        debug 0 "File removed."
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
OS="$(uname)"
OPT_FILTERS=()

# loop for options
while getopts ":c:f:hrqv:V" opt; do
    case "${opt}" in
        "c")
            SCRIPTCONF="${OPTARG}"
            ;;
        "f")
            OPT_FILTERS+=("${OPTARG,,}")
            ;;
        "q")
            OPT_DBG=-1
            ;;
        "r")
            method="remove"
            ;;
        "v")
            OPT_DBG="${OPTARG}"
            VERBOSE=("-v")
            ;;
        "V")
            # <main> is replaced by release process
            echo "Version: <main>"
            exit 0
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

if [ -n "${OPT_FILTERS[*]}" ]; then
    if unknown="$(grep -vxFf <(printf '%s\n' "${FILTERTYPES[@]}") <(printf '%s\n' "${OPT_FILTERS[@]}"))"; then
        error "Unknown filters: ${unknown}"
        exit 1
    fi
fi

prepare

trap 'rm -fr "${TMPDIR}";exit' INT TERM EXIT

lock
debug 2 "URL-List: ${URLS[*]}"
debug 2 "Privoxy-Configdir: ${PRIVOXY_DIR}"
debug 2 "Temporary directory: ${TMPDIR}"
"${method}"

# restore default exit command
trap - INT TERM EXIT
if [ "${DBG}" -lt 3 ]; then
    rm -r "${VERBOSE[@]}" "${TMPDIR}"
fi
exit 0

# vim: ts=4 sw=4 et
