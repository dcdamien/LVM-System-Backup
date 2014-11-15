#!/bin/bash
#
# Author: MrCrankHank
#

# Define default vars
start=`date +%s`
hostname=$(</etc/hostname)
LOCKFILE=/var/run/lvm_system_backup.lock
NAGIOS_LOG=/var/log/lvm_system_backup_nagios_log
LVS=/tmp/lvs
RED='\e[0;31m'
NC='\e[0m'
ORANGE='\e[0;33m'
GREEN='\e[0;32m'
VERBOSE=0

# Abort if lockfile is found
if [ -f $LOCKFILE ]; then
	echo -e "${RED}Error: ${NC}Backup is already running!"
	exit 1
fi

# Look for config in /etc/default
if [ -f /etc/default/lvm_system_backup_config ]; then
	. /etc/default/lvm_system_backup_config

if [ $VERBOSE == 1 ]; then
	echo -e "${ORANGE}Verbose: ${NC}Found the config file under /etc/default/lvm_system_backup_config"
fi

else
	if [ -z $1 ]; then
		echo -e "${RED}Error: ${NC}Can't find the config file at default location"
		echo -e "${RED}Error: ${NC}Please specify one as first parameter"
		exit 1
	fi

	if [ $VERBOSE == 1 ]; then
		echo -e "${ORANGE}Verbose: ${NC}The location of the config file is in the first parameter. Location: $1"
	fi

	if ! [ -f $1 ]; then
		echo -e "${RED}Error: ${NC}Can't find config file at $1"
		echo -e "${RED}Error: ${NC}Please check the path and come back"

		if [ $VERBOSE == 1 ]; then
			echo -e "${ORANGE}Verbose: ${NC}Couldn't find the config file neither at the default path nor as the first parameter"
		fi
		exit 1
	fi
fi

# Check if $BACKUP_BOOT var is set to 0/1
if [ $VERBOSE == 1 ]; then
	echo -e "${ORANGE}Verbose: ${NC}Checking if the BACKUP_BOOT option is configured"
fi

if [ -z $BACKUP_BOOT ]; then
	echo -e "${RED}Error: ${NC}BACKUP_BOOT is not configured!"
	echo -e "${RED}Error: ${NC}Please check the config file!"
	exit 1
fi

# Check if all vars from the config file are configured
if [ $VERBOSE == 1 ]; then
	echo -e "${ORANGE}Verbose: ${NC}Checking if the BACKUP_BOOT option is enabled"
fi

if [ $BACKUP_BOOT == 1 ]; then
	if [ $VERBOSE == 1 ]; then
		echo -e "${ORANGE}Verbose: ${NC}BACKUP_BOOT is enabled"
		echo -e "${ORANGE}Verbose: ${NC}Checking if all necessary vars are configured"
	fi

	if [[ -z "$VG_NAME" || -z "$DIR" || -z "$HOST" || -z "$USER" || -z "$DISK" || -z "$BOOT" ]]; then
		echo -e "${RED}Error: ${NC}Important vars are missing!"
		echo -e "${RED}Error: ${NC}Please check the config file!"
		exit 1
	fi
else
	if [ $VERBOSE == 1 ]; then
		echo -e "${ORANGE}Verbose: ${NC}BACKUP_BOOT is disabled"
		echo -e "${ORANGE}Verbose: ${NC}Checking if all necessary vars are configured"
	fi

	if [[ -z "$VG_NAME" || -z "$DIR" || -z "$HOST" || -z "$USER" ]]; then
		echo -e "${RED}Error: ${NC}Important vars are missing!"
		echo -e "${RED}Error: ${NC}Please check the config file!"
		exit 1
	fi
fi

# Check if the specified volume group is there
if [ $VERBOSE == 1 ]; then
	echo -e "${ORANGE}Verbose: ${NC}Checking if the volume group $VG_NAME exists"
fi

if ! [ -d /dev/$VG_NAME ]; then
	echo -e "${RED}Error: ${NC}VG $VG_NAME not found!"
	exit 1
fi

# Checks for the backup boot feature
if [ $BACKUP_BOOT == 1 ]; then
	if [ $VERBOSE == 1 ]; then
		echo -e "${ORANGE}Verbose: ${NC}Checking if the disk $DISK exists"
	fi

	if ! [ -b $DISK ]; then
		echo -e "${RED}Error: ${NC}Disk $DISK not found!"
		exit 1
	fi

	if [ $VERBOSE == 1 ]; then
		echo -e "${ORANGE}Verbose: ${NC}Checking if the boot disk $BOOT exists"
	fi

	if ! [ -b $BOOT ]; then
		echo -e "${RED}Error: ${NC}Boot Disk $BOOT not found!"
		exit 1
	fi

	if [ $VERBOSE == 1 ]; then
		echo -e "${ORANGE}Verbose: ${NC}Checking if the boot disk $BOOT is mounted on /boot"
	fi

	MOUNT=$(mount | grep /boot | grep -o $BOOT)

	if [ -z $MOUNT ]; then
		echo -e "${RED}Error: ${NC}Boot disk $BOOT is not mounted on /boot"
		exit 1
	fi
fi

# Check if there is enough free space in the specified volume group to create a snapshot
if [ $VERBOSE == 1 ]; then
	echo -e "${ORANGE}Verbose: ${NC}Checking if there is enough free space in the VG $VG_NAME to create a $SIZE snapshot"
fi

SIZE_SNAPSHOT=$(echo $SIZE | sed -e 's/g//g' | sed -e 's/,/./g' | sed -e 's/G//g')
SIZE_FREE=$(lvs /dev/$VG_NAME -o vg_free | tail -1 | tr -d ' ' | sed -e 's/g//g' | sed -e 's/,/./g')
SIZE_OUT=$(bc <<< "${SIZE_FREE}-$SIZE_SNAPSHOT")
CHECK_SIZE=$(echo $SIZE | grep -c -)
SIZE_OUT=$(echo ${SIZE}G | sed -e 's/-//g')

if ! [ $CHECK_SIZE == 0 ]; then
	echo -e "${RED}Error: ${NC}Not enough free space in VG $VG to create a snapshot"
	echo -e "${RED}Error: ${NC}Need at least $SIZE_OUT space more"
	exit 1
fi

# Check if the excluded logical volumes are existing
COUNTER=0
while [ $COUNTER -lt ${#LV_EXCLUDE[@]} ]; do
        if ! [ -b /dev/$VG_NAME/${LV_EXCLUDE[$COUNTER]} ]; then
                echo -e "${RED}Error: ${NC}Excluded LV ${LV_EXCLUDE[$COUNTER]} doesn't exist"
                exit 1
        fi
        let COUNTER=COUNTER+1
done

# Create dir var with subfolders
datum=`date +%m/%d/%y`
DIR_DATE=`date +%m-%d-%y`
time=`date +"%T"`
DIR=$DIR/$hostname/$DIR_DATE

# Create lock file
if [ $VERBOSE == 1 ]; then
	echo -e "${ORANGE}Verbose: ${NC}Creating lock file. Things are getting pretty serious"
fi

touch $LOCKFILE

# Create list with logical volumes
if [ $VERBOSE == 1 ]; then
	echo -e "${ORANGE}Verbose: ${NC}Creating list $LVS with all logical volumes in VG $VG_NAME"
fi

lvdisplay $VG_NAME | grep -e "LV Name" | tr -d ' ' | sed -e 's/LVName//g' > $LVS

if [ $? -ne 0 ]; then
	echo -e "${RED}Error: ${NC}Couldn't creat the list with logical volumes"
	exit 1
fi

# Exclude logical volumes
if [ $VERBOSE == 1 ]; then
	echo -e "${ORANGE}Verbose: ${NC}Deleting all excluded logical volumes from the file $LVS"
	echo -e "${ORANGE}Verbose: ${NC}Excluded volume/s is/are: ${LV_EXCLUDE[@]}"
fi

if ! [ ${#LV_EXCLUDE[@]} -eq 0 ]; then
        COUNTER=0
        while [ $COUNTER -lt ${#LV_EXCLUDE[@]} ]; do
                sed -i "/${LV_EXCLUDE[$COUNTER]}/d" $LVS
                let COUNTER=COUNTER+1
        done
fi

# Exit trap to delete the snapshots and the lockfile
function finish {
	if [ $VERBOSE == 1 ]; then
		echo -e "${ORANGE}Verbose: ${NC}Cleaning up..."
	fi

        while read lv; do
                if [ -e /dev/$VG_NAME/${lv}_snap ]; then
                        lvremove -f /dev/$VG_NAME/${lv}_snap
			if [ $? -ne 0 ]; then
				echo -e "${RED}Error: ${NC}Couldn't remove ${lv}_snap"
				exit 1
			fi
                fi
        done < $LVS

        if [ -f $LOCKFILE ]; then
		rm $LOCKFILE
	fi

	if [ $VERBOSE == 1 ]; then
		echo -e "${ORANGE}Verbose: ${NC}Done"
	fi
}
trap finish EXIT

function backup_layout {
	# Backup partition table

	if [ $VERBOSE == 1 ]; then
		echo -e "${ORANGE}Verbose: ${NC}Backing up partiton table to /tmp/part_table"
	fi

	if [ -d /tmp ]; then
		touch /tmp/.test
		if [ $? -ne 0 ]; then
			echo -e "${RED}Error: ${NC}/tmp not writeable"
			exit 1
		fi
	else
		echo -e "${RED}Error: ${NC}/tmp doesn't exist"
		exit 1
	fi

	sfdisk --quiet -d $DISK > /tmp/part_table

	if [ $VERBOSE == 1 ]; then
		echo -e "${ORANGE}Verbose: ${NC}Sending partition table backup to $HOST:$DIR"
	fi

	if [ -f /tmp/part_table ]; then
		scp /tmp/part_table $USER@$HOST:$DIR/part_table > /dev/null

		if [ $? -ne 0 ]; then
			echo -e "${RED}Error: ${NC}Cannot login or connect to $HOST"
			exit 1
		fi
	else
		echo -e "${RED}Error: ${NC}Can't copy /tmp/part_table to $HOST. File doens't exist"
		exit 1
	fi

	if [ $VERBOSE == 1 ]; then
		echo -e "${ORANGE}Verbose: ${NC}Deleting partition table in /tmp/part_table"
	fi

	rm /tmp/part_table

	# Backup lvm structure
	if [ $VERBOSE == 1 ]; then
		echo -e "${ORANGE}Verbose: ${NC}Backing up lvm structure to /tmp/lvm_structure"
	fi

	vgcfgbackup -f /tmp/lvm_structure /dev/$VG_NAME > /dev/null

	if [ $? -ne 0 ]; then
		echo -e "${RED}Error: ${NC}Couldn't backup the lvm structure of volume group $VG_NAME"
		exit 1
	fi

	if [ $VERBOSE == 1 ]; then
		echo -e "${ORANGE}Verbose: ${NC}Sending lvm structure to $HOST:$DIR"
	fi

	if [ -f /tmp/lvm_structure ]; then
		scp /tmp/lvm_structure ${USER}@$HOST:$DIR/lvm_structure > /dev/null

		if [ $? -ne 0 ]; then
			echo -e "${RED}Error: ${NC}Cannot login or connect to $HOST"
			exit 1
		fi
	else
		echo -e "${RED}Error: ${NC}Can't copy /tmp/lvm_structure to $HOST. File doens't exist"
		exit 1
	fi

	if [ $VERBOSE == 1 ]; then
		echo -e "${ORANGE}Verbose: ${NC}Deleting lvm structure in /tmp/lvm_structure"
	fi

	rm /tmp/lvm_structure
}

function backup_lvs {
	# Create a snapshot of every volume and copy it using dd
	if [ $VERBOSE == 1 ]; then
		echo -e "${ORANGE}Verbose: ${NC}Starting loop for every volume in $LVS"
	fi

	while read lv; do
		if [ $VERBOSE == 1 ]; then
			echo -e "${ORANGE}Verbose: ${NC}Creating a $SIZE snapshot named ${lv}_snap of LV ${lv} in VG $VG_NAME"
		fi
		lvcreate --snapshot -L $SIZE -n ${lv}_snap /dev/$VG_NAME/$lv > /dev/null

		if [ $? -ne 0 ]; then
			echo -e "${RED}Error: ${NC}Couldn't create a $SIZE snapshot named ${lv}_snap of LV ${lv} in VG $VG_NAME"
			exit 1
		fi

		if [ $VERBOSE == 1 ]; then
			echo -e "${ORANGE}Verbose: ${NC}Copy the compressed volume ${lv} via dd to $HOST"
		fi
		dd if=/dev/$VG_NAME/${lv}_snap | gzip -1 - | ssh ${USER}@$HOST dd of=$DIR/${lv}.img.gz

		if [ $? -ne 0 ]; then
			echo -e "${RED}Error: ${NC}Couldn't copy the compressed volume ${lv} to $HOST"
			exit 1
		fi

		if [ $VERBOSE == 1 ]; then
			echo -e "${ORANGE}Verbose: ${NC}Removing the snapshot ${lv}_snap"
		fi
		lvremove -f /dev/$VG_NAME/${lv}_snap > /dev/null

		if [ $? -ne 0 ]; then
			echo -e "${RED}Error: ${NC}Couldn't delete the snapshot named ${lv}_snap of lv ${lv}"
			exit 1
		fi
	done < $LVS
}

# Create remote backup dir
if [ $VERBOSE == 1 ]; then
	echo -e "${ORANGE}Verbose: ${NC}Creating remote dir $DIR to store the backups on $HOST"
fi
ssh ${USER}@$HOST mkdir -p $DIR

if [ $? -ne 0 ]; then
	echo -e "${RED}Error: ${NC}Couldn't create the remote dir $DIR to store the backups"
	exit 1
fi

# Backup lvm and mbr layout
if [ $VERBOSE == 1 ]; then
	echo -e "${ORANGE}Verbose: ${NC}Starting the backups of lvm and mbr layout..."
fi
backup_layout
if [ $VERBOSE == 1 ]; then
	echo -e "${ORANGE}Verbose: ${NC}...finished"
fi

if [ $BACKUP_BOOT == 1 ]; then
	# Create image of /boot
	if [ $VERBOSE == 1 ]; then
		echo -e "${ORANGE}Verbose: ${NC}Copy $BOOT to $HOST via dd"
	fi

	dd if=$BOOT | gzip -1 - | ssh ${USER}@$HOST dd of=$DIR/boot.img.gz

	if [ $? -ne 0 ]; then
		echo -e "${RED}Error: ${NC}Couldn't copy the boot disk $BOOT  to $HOST"
		exit 1
	fi

	# Create image of mbr with grub
	if [ $VERBOSE == 1 ]; then
		echo -e "${ORANGE}Verbose: ${NC}Create a 512 byte image of the mbr"
	fi
	dd if=$DISK bs=512 count=1 | gzip -1 - | ssh ${USER}@$HOST dd of=$DIR/mbr.img.gz

	if [ $? -ne 0 ]; then
		echo -e "${RED}Error: ${NC}Couldn't create an image of the mbr"
	fi
fi

# Backup the logical volumes
backup_lvs

# Remove lock file
if [ $VERBOSE == 1 ]; then
	echo -e "${ORANGE}Verbose: ${NC}Removing the lock file, if exists"
fi

if [ -f $LOCKFILE ]; then
	rm $LOCKFILE
fi

# Calculate runtime
end=`date +%s`
if [ $VERBOSE == 1 ]; then
	echo -e "${ORANGE}Verbose: ${NC}Execution took $((end-start)) seconds"
fi

# Write nagios log
if ! [ -z $NAGIOS ]; then
	if [ $NAGIOS == 1 ]; then

		if [ $VERBOSE == 1 ]; then
			echo -e "${ORANGE}Verbose: ${NC}Creating log file for nagios plugin"
		fi

		if [ -f $NAGIOS_LOG ]; then
			rm $NAGIOS_LOG
		fi
		echo "$hostname" >> $NAGIOS_LOG
		echo "$datum" >> $NAGIOS_LOG
		echo "$time" >> $NAGIOS_LOG
		echo "successful" >> $NAGIOS_LOG
	fi
fi

echo -e "${GREEN}Backup successful!"
