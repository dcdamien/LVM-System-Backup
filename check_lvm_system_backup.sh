#!/bin/bash
#
# Author: MrCrankHank
#

if [ -z $1 ]; then
	echo "./check_lvm_system_backup.sh <MAX_OLD_DAYs> <NAGIOS_LOG_FILE>"
	echo
	echo "MAX_OLD_DAYs: 		The script will trigger a critical alert if the backup is older then the days specified in this var. No default value"
	echo
	echo "NAGIOS_LOG_FILE: 	This parameter allows you to specify the path for the nagios log file. Default is /var/log/lvm_system_backup_nagios_log"
	echo
	exit 1
fi

MAX_OLD=$1
RED='\e[0;31m'
NC='\e[0m'

if ! [ -z $2 ]; then
	NAGIOS_LOG=$2
else
	NAGIOS_LOG="/var/log/lvm_system_backup_nagios_log"
fi

if ! [ -f $NAGIOS_LOG ]; then
	echo -e "${RED}Error: ${NC}Can't find log file at $NAGIOS_LOG"
	exit 3
fi

TODAY=`date +%m/%d/%y`
TODAY=$(date -d "$TODAY" '+%s')

DATE_LOG=$(head -n2 $NAGIOS_LOG | tail -n1)
DATE_LOG_SEC=$(date +%m/%d/%y -d "$DATE_LOG + $MAX_OLD day")
DATE_LOG_SEC=$(date -d $DATE_LOG_SEC '+%s')

if [ $TODAY -ge $DATE_LOG_SEC ]; then
	echo "Critical - LVM system backup is from $DATE_LOG"
	exit 2
else
	echo "OK - LVM system backup is from $DATE_LOG"
	exit 0
fi
