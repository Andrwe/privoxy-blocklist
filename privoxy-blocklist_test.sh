#!/bin/bash
#
######################################################################
#
#                  Author: Andrwe Lord Weber
#                  Mail: lord-weber-andrwe<at>renona-studios<dot>org
#                  Version: 0.2
#                  URL: http://andrwe.dyndns.org/doku.php/blog/scripting/bash/privoxy-blocklist
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
#                     calss->id combination
#
######################################################################

######################################################################
#
#                  script variables and functions
#
######################################################################

# array of URL for AdblockPlus lists
URLS=("https://easylist-downloads.adblockplus.org/easylist.txt" "https://easylist-downloads.adblockplus.org/easylistgermany.txt" "http://adblockplus.mozdev.org/easylist/easylist.txt")
# privoxy config dir (default: /etc/privoxy/)
CONFDIR=/etc/privoxy
# directory for temporary files
TMPDIR=/tmp/privoxy-blocklist-test
TMPNAME=$(basename ${0})

######################################################################
#
#                  No changes needed after this line.
#
######################################################################

function usage()
{
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

[ ${UID} -ne 0 ] && echo -e "Root privileges needed. Exit.\n\n" && usage && exit 1

# check whether an instance is already running
[ -e ${TMPDIR}/${TMPNAME}.lock ] && echo "An Instance of ${TMPNAME} is already running. Exit" && exit

DBG=0

function debug()
{
	[ ${DBG} -ge ${2} ] && echo -e "${1}"
}

function escapeLine()
{
	local pline="$1"
	pline="${pline//./\.}"
	pline="${pline//\?/\?}"
	pline="${pline//\*/\*}"
	pline="${pline//(/\(}"
	pline="${pline//)/\)}"
	pline="${pline//[/\[}"
	pline="${pline//]/\]}"
	pline="${pline//\^/[\/\&:\?=_]}"
	pline="${pline/||/\.}"
	pline="${pline/|/^}"
	pline="${pline/%|/\$}"
	echo "$pline"
}
function main()
{
	local cpoptions=""
	[ ${DBG} -gt 0 ] && cpoptions="-v"

	for url in ${URLS[@]}
	do
		debug "Processing ${url} ...\n" 0
		local file=${TMPDIR}/$(basename ${url})
		local actionfile=${file%\.*}.script.action
		local whitefile=${file%\.*}.script.white
		local whiteimgfile=${file%\.*}.script.whiteimg
		local filterfile=${file%\.*}.script.filter
		local list=$(basename ${file%\.*})
	
		# download list
		debug "Downloading ${url} ..." 0
		wget -t 3 --no-check-certificate -O ${file} ${url} >${TMPDIR}/wget-${url//\//#}.log 2>&1
		debug "$(cat ${TMPDIR}/wget-${url//\//#}.log)" 2
		debug ".. downloading done." 0
		[ "$(grep -E '^\[Adblock.*\]$' ${file})" == "" ] && echo "The list recieved from ${url} isn't an AdblockPlus list. Skipped" && continue
	
		local line pline wline pfile
		# blacklist of urls
		debug "Creating actionfile for ${list} ..." 1
		echo -e "{ +block{${list}} }" > ${actionfile}
		debug "... creating filterfile for ${list} ..." 1
		echo "FILTER: ${list} Tag filter of ${list}" > ${filterfile}
		debug "... creating whitlistfile for urls ..." 1
		# whitelist of urls
		echo "{ -block }" > ${whitefile}
		# whitelist of images for urls
		debug "... creating whitlistfile of images for urls ..." 1
		echo "{ -block +handle-as-image }" > ${whiteimgfile}
		debug "... processing listfile ..." 0

		# convert AdblockPlus list to Privoxy list
		while read line
		do
	#		debug "total line: $line" 2
			if [[ ${line:0:1} = ! ]] || [[ $line =~ ^[Adblock ]]
			then
				continue
			fi
			# set filter for html elements
			if [[ ${line:0:1} = "#" ]]
			then
				pfile="$filterfile"
				wline="${line:2}"
				if [[ ${wline:0:1} = \# ]]
				then
					wline="${wline:1}"
					pline="<s|<([a-zA-Z0-9]+)\s+.*id=.?${wline/[*/}.*>.*<\/\1>||g"
				elif [[ ${wline:0:1} = \. ]]
				then
					pline="s|<([a-zA-Z0-9]+)\s+.*class=.?${wline:1}.*>.*<\/\1>||g"
				elif [[ ${wline:0:2} = a\[ ]]
				then
					pline="s|<a.*${wline:2:${#wline}-1}.*>.*<\/a>||g"
				elif [[ ${wline} =~ ^[a-zA-Z0-9]*.* ]]
				then
					local tag="${wline/[#.]*/}"
					wline="${wline:${#tag}}"
					if [[ ${wline:0:1} = \# ]]
					then
						wline="${wline:1}"
						pline="<s|<$tag\s+.*id=.?${wline/[*/}.*>.*<\/$tag>||g"
					elif [[ ${wline:0:1} = \. ]]
					then
						pline="s|<$tag\s+.*class=.?${wline:1}.*>.*<\/$tag>||g"
					fi
					unset tag
				elif [[ ${wline:0:1} = \[ ]]
				then
					local firstpart="${wline/=*/}"
					local secpart="${wline/*=/}"
					pline="s|${firstpart:1}=${secpart:0:${#secpart}-1}.*>||g"
				fi
				if [[ -n "${pline}" ]]
				then
					pline="$(escapeLine "$pline")"
				fi
			# whitelist of urls
			elif [[ ${line:0:2} = @@ ]]
			then
				pfile="$whitefile"
				wline="${line:2}"
				if [[ $line =~ \$.*image ]]
				then
					wline="${wline//\$*/}"
					pfile="$whiteimgfile"
				fi
				if [[ $wline =~ [\$\#] ]]
				then
					continue
				fi
				if [[ -n "${wline}" ]]
				then
					pline="$(escapeLine "$wline")"
				fi
				if [[ $pline =~ \| ]]
				then
					continue
				fi
			elif [[ ! $line =~ [\$\#] ]]
			then
				pfile="$actionfile"
				wline="$line"
				if [[ -n "${wline}" ]]
				then
					pline="$(escapeLine "$wline")"
				fi
			fi
			[[ -n "$pfile" ]] && echo "$pline" >> "$pfile"
	#		debug "written line: $pline" 2
	#		debug "written file: $pfile" 2
			unset pline wline pfile
		done < "${file}"

		debug "... adding filterfile to actionfile ..." 1
		echo "{ +filter{${list}} }" >> ${actionfile}
		echo "*" >> ${actionfile}
		debug "... adding whitelist to actionfile ..." 1
		cat "$whitefile" >> "$actionfile"
		debug "... adding image handler to actionfile ..." 1
		cat "$whiteimgfile" >> "$actionfile"
		debug "... created actionfile for ${list}." 1

		debug "... done." 0

#		domains=$(sed ${sedoptions} '/^#/d;/#/!d;s/,~/,\*/g;s/~/;:\*/g;s/^\([a-zA-Z]\)/;:\1/g' ${file})
#		[ -n "${domains}" ] && debug "... creating domainbased filterfiles ..." 1
#		debug "Found Domains: ${domains}." 2
#		ifs=$IFS
#		IFS=";:"
#		for domain in ${domains}
#		do
#			dns=$(echo ${domain} | awk -F ',' '{print $1}' | awk -F '#' '{print $1}')
#			debug "Modifying line: ${domain}" 2
#			debug "   ... creating filterfile for ${dns} ..." 1
#	#		sed '' ${file} > ${file%\.*}-${dns%~}.script.filter
#			debug "   ... filterfile created ..." 1
#			debug "   ... adding filterfile for ${dns} to actionfile ..." 1
#	#		echo "{ +filter{${list}-${dns}} }" >> ${actionfile}
#	#		echo "${dns}" >> ${actionfile}
#			debug "   ... filterfile added ..." 1
#		done
#		IFS=${ifs}
#		debug "... all domainbased filterfiles created ..." 1

	
		# install Privoxy actionsfile
		cp ${cpoptions} ${actionfile} ${CONFDIR}
		if [ "$(grep $(basename ${actionfile}) ${CONFDIR}/config)" == "" ] 
		then
			debug "\nModifying ${CONFDIR}/config ..." 0
			sed "s/^actionsfile user\.action/actionsfile $(basename ${actionfile})\nactionsfile user.action/" ${CONFDIR}/config > ${TMPDIR}/config
			debug "... modification done.\n" 0
			debug "Installing new config ..." 0
			cp ${cpoptions} ${TMPDIR}/config ${CONFDIR}
			debug "... installation done\n" 0
		fi	
		# install Privoxy filterfile
		cp ${cpoptions} ${filterfile} ${CONFDIR}
		if [ "$(grep $(basename ${filterfile}) ${CONFDIR}/config)" == "" ] 
		then
			debug "\nModifying ${CONFDIR}/config ..." 0
			sed "s/^\(#*\)filterfile user\.filter/filterfile $(basename ${filterfile})\n\1filterfile user.filter/" ${CONFDIR}/config > ${TMPDIR}/config
			debug "... modification done.\n" 0
			debug "Installing new config ..." 0
			cp ${cpoptions} ${TMPDIR}/config ${CONFDIR}
			debug "... installation done\n" 0
		fi	
	
		debug "... ${url} installed successfully.\n" 0
	done
}

# create temporary directory and lock file
mkdir -p ${TMPDIR}
touch ${TMPDIR}/${TMPNAME}.lock

# set command to be run on exit
[ ${DBG} -le 2 ] && trap "rm -fr ${TMPDIR};exit" INT TERM EXIT

# loop for options
while getopts ":hrqv:" opt
do
	case "${opt}" in 
		"h")
			usage
			exit 0
			;;
		"v")
			DBG="${OPTARG}"
			;;
		"q")
			DBG=-1
			;;
		"r")
			echo "Do you really want to remove all build lists?(y/N)"
			read choice
			[ "${choice}" != "y" ] && exit 0
			rm -rf ${CONFDIR}/*.script.{action,filter} && \
			sed '/^actionsfile .*\.script\.action$/d;/^filterfile .*\.script\.filter$/d' -i ${CONFDIR}/config && \
			echo "Lists removed." && exit 0
			echo -e "An error occured while removing the lists.\nPlease have a look into ${CONFDIR} whether there are .script.* files and search for *.script.* in ${CONFDIR}/config."
			exit 1
			;;
		":")
			echo "${TMPNAME}: -${OPTARG} requires an argument" >&2
			exit 1
			;;
	esac
done

debug "URL-List: ${URLS}\nPrivoxy-Configdir: ${CONFDIR}\nTemporary directory: ${TMPDIR}" 2
main

# restore default exit command
trap - INT TERM EXIT
[ ${DBG} -lt 2 ] && rm -r ${TMPDIR}
[ ${DBG} -eq 2 ] && rm -vr ${TMPDIR}
exit 0
