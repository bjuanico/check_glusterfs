#!/bin/bash

# Bernardo Juanico, bjuanico@gmail.com
# Changes:
# version 1.1:
# Added support for TB sized drives by emitor@gmail.com
# version 1.2:
# The script now autodiscovers the numbers of bricks and replicas
# The script now outputs the correct size when more than 1 x 2 bricks exists
# version 1.3:
# The script now alarms on bad volume status
#
# 2013, Mark Ruys, mark.ruys@peercode.nl
# This Nagios script was written against version 3.3 & 3.4 of Gluster.  Older
# versions will most likely not work at all with this monitoring script.
#
# Gluster currently requires elevated permissions to do anything.  In order to
# accommodate this, you need to allow your Nagios user some additional
# permissions via sudo.  The line you want to add will look something like the
# following in /etc/sudoers (or something equivalent):
#
# Defaults:nagios !requiretty
# nagios ALL=(root) NOPASSWD:/usr/sbin/gluster volume status [[\:graph\:]]* detail,/usr/sbin/gluster volume heal [[\:graph\:]]* info
#
# That should give us all the access we need to check the status of any
# currently defined peers and volumes.

# Inspired by a script of Mark Nipper



PATH=/sbin:/bin:/usr/sbin:/usr/bin

PROGNAME=$(basename -- $0)
PROGPATH=`echo $0 | sed -e 's,[\\/][^\\/][^\\/]*$,,'`
REVISION="1.3"

. $PROGPATH/utils.sh

# parse command line
usage () {
  echo ""
  echo "USAGE: "
  echo "  $PROGNAME -v VOLUME -n BRICKS [-w GB -c GB]"
  echo "     -n BRICKS: number of bricks (Unused, deprecated, now autodiscovered )"
  echo "     -w and -c values in GB"
  exit $STATE_UNKNOWN
}

while getopts "v:n:w:c:" opt; do
  case $opt in
    v) VOLUME=${OPTARG} ;;
    n) BRICKS=${OPTARG} ;;
    w) WARN=${OPTARG} ;;
    c) CRIT=${OPTARG} ;;
    *) usage ;;
  esac
done

if [ -z "${VOLUME}" ]; then
  usage
fi
Exit () {
	echo "$1: ${2:0}"
	status=STATE_$1
	exit ${!status}
}

# check for commands
for cmd in basename bc awk sudo pidof gluster; do
	if ! type -p "$cmd" >/dev/null; then
		Exit UNKNOWN "$cmd not found"
	fi
done

# check for glusterd (management daemon)
if ! pidof glusterd &>/dev/null; then
	Exit CRITICAL "glusterd management daemon not running"
fi

# check for glusterfsd (brick daemon)
if ! pidof glusterfsd &>/dev/null; then
	Exit CRITICAL "glusterfsd brick daemon not running"
fi

# get volume heal status
heal=0
for entries in $(sudo gluster volume heal ${VOLUME} info | awk '/^Number of entries: /{print $4}'); do
	if [ "$entries" -gt 0 ]; then
		let $((heal+=entries))
	fi
done
if [ "$heal" -gt 0 ]; then
	errors=("${errors[@]}" "$heal unsynched entries")
fi

# get volume status
bricksfound=0
shopt -s nullglob
total=0
while read -r line; do
	field=($(echo $line))
	case ${field[0]} in
	Brick)
		brick=${field[@]:2}
		;;
	Disk)
		key=${field[@]:0:3}
		if [ "${key}" = "Disk Space Free" ]; then
			freeunit=${field[@]:4}
			free=${freeunit:0:${#freeunit}-2}
			unit=${freeunit#$free}
			if [ "$unit" != "GB" ] && [ "$unit" != "TB" ]; then
				Exit UNKNOWN "unknown disk space size $freeunit"
			fi
			total=$(echo "${total} + ${free}" | bc -q)
			if [ "$unit" = "TB" ]; then
				free=$(echo "${free} * 1024" | bc -q)
			fi
			free=$(echo "${free} / 1" | bc -q)
		fi
		;;
	Online)
		online=${field[@]:2}
		if [ "${online}" = "Y" ]; then
			let $((bricksfound++))
		else
			errors=("${errors[@]}" "$brick offline")
		fi
		;;
	esac
done < <(sudo gluster volume status ${VOLUME} detail)



#GLUSTER VOLUME INFO
while read -r line; do
	field=($(echo $line))
	case ${field[0]} in
	Status:)
		status=${field[@]:1}
		if [ "${status}" != "Started" ]; then
		Exit CRITICAL "Critical: Status: $status"
		fi
		;;
	Number)
		replica=${field[@]:3:1}
		bricks=${field[@]:5:1}
		BRICKS=$(echo "${replica} * ${bricks}" | bc -q)
		;;
	esac
done < <(sudo gluster volume info ${VOLUME} )

total=$(echo "${total} / ${BRICKS} * ${replica}" | bc -q)
free=$(echo "${total} / 1" | bc -q)

if [ "$unit" = "TB" ]; then
	free=$(echo "${free} * 1024" | bc -q)
fi

freeunit=$total$unit


if [ $bricksfound -eq 0 ]; then
	Exit CRITICAL "no bricks found"
elif [ $bricksfound -lt $BRICKS ]; then
	errors=("${errors[@]}" "found $bricksfound bricks, expected $BRICKS ")
fi

if [ -n "$CRIT" -a -n "$WARN" ]; then
	if [ $CRIT -ge $WARN ]; then
		Exit UNKNOWN "critical threshold below warning"
	elif [ $free -lt $CRIT ]; then
		Exit CRITICAL "free space ${freeunit}"
	elif [ $free -lt $WARN ]; then
		errors=("${errors[@]}" "free space ${freeunit}")
	fi
fi

# exit with warning if errors
if [ -n "$errors" ]; then
	sep='; '
	msg=$(printf "${sep}%s" "${errors[@]}")
	msg=${msg:${#sep}}

	Exit WARNING "${msg}"
fi

# exit with no errors
Exit OK "${bricksfound} bricks; free space ${freeunit}"
