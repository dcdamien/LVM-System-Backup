#!/bin/bash
#
# Author: MrCrankHank
#

# Define default vars
hostname=$(</etc/hostname)
LOCKFILE=/var/run/lvm_system_backup.lock
LVS=/tmp/lvs

# Abort if lockfile is found
if [ -f $LOCKFILE ]; then
	echo "Backup is already running!"
	exit 1
fi

# Look for config in /etc/default
if [ -f /etc/default/lvm_system_backup_config ]; then
        . /etc/default/lvm_system_backup_config
else
	if [ -z $1 ]; then
		echo "Can't find config file at default location"
		echo "Please specify one as first parameter"
		exit 1
	fi

	if ! [ -f $1 ]; then
		echo "Can't find config file at $1"
		echo "Please check the path and come back"
		exit 1
	fi
fi

# Check if $BACKUP_BOOT var is set to 0/1
if [ -z $BACKUP_BOOT ]; then
	echo "BACKUP_BOOT is not configured!"
	echo "Please check the config file!"
	exit 1
fi

# Check if all vars from the config file are configured
if [ $BACKUP_BOOT == 1 ]; then
	if [[ -z "$VG_NAME" && -z "$DIR" && -z "$HOST" && -z "$USER" && -z "$DISK" && -z "$BOOT" ]]; then
		echo "Important vars are missing!"
		echo "Please check the config file!"
		exit 1
	fi
else
	if [[ -z "$VG_NAME" && -z "$DIR" && -z "$HOST" && -z "$USER" ]]; then
		echo "Important vars are missing!"
		echo "Please check the config file!"
		exit 1
	fi
fi

# Check if the specified volume group is there
if [ -d /dev/$VG_NAME ]; then
	true
else
	echo "VG $VG_NAME not found!"
	exit 1
fi

# Create dir var with subfolders
datum=`date +%d.%m.%y`
time=`date +"%T"`
DIR=$DIR/$hostname/$datum

# Create lock file
touch $LOCKFILE

# Create list with logical volumes
lvdisplay $VG_NAME | grep -e "LV Name" | tr -d ' ' | sed -e 's/LVName//g' > $LVS

# Exclude logical volumes
if ! [ ${#LV_EXCLUDE[@]} -eq 0 ]; then
        COUNTER=0
        while [ $COUNTER -lt ${#LV_EXCLUDE[@]} ]; do
                sed -i "/${LV_EXCLUDE[$COUNTER]}/d" $LVS
                let COUNTER=COUNTER+1
        done
fi

# Exit trap to delete the snapshots and the lockfile
function finish {
        while read lv; do
                if [ -e /dev/$VG_NAME/${lv}_snap ]; then
                        lvremove -f /dev/$VG_NAME/${lv}_snap
                fi
        done < /tmp/lvs
        rm $LOCKFILE
}
trap finish EXIT

function backup_layout {
	# Backup partition table
	sfdisk -d $DISK > /tmp/part_table
	scp /tmp/part_table ${USER}@$HOST:$DIR/part_table
	rm /tmp/part_table

	# Backup lvm structure
	vgcfgbackup -f /tmp/lvm_structure /dev/$VG_NAME
	scp /tmp/lvm_structure ${USER}@$HOST:$DIR/lvm_structure
	rm /tmp/lvm_structure
}

function backup_lvs {
	# Create a snapshot of every volume and copy it using dd
	while read lv; do
		lvcreate --snapshot -L $SIZE -n ${lv}_snap /dev/$VG_NAME/$lv
		dd if=/dev/$VG_NAME/${lv}_snap | gzip -1 - | ssh ${USER}@$HOST dd of=$DIR/${lv}.img.gz
		lvremove -f /dev/$VG_NAME/${lv}_snap
	done < /tmp/lvs
}

# Create remote backup dir
ssh ${USER}@$HOST mkdir -p $DIR

# Backup lvm and mbr layout
backup_layout

if [ $BACKUP_BOOT == 1 ]; then
	# Create image of /boot
	dd if=$BOOT | gzip -1 - | ssh ${USER}@$HOST dd of=$DIR/boot.img.gz

	# Create image of mbr with grub
	dd if=$DISK bs=512 count=1 | gzip -1 - | ssh ${USER}@$HOST dd of=$DIR/mbr.img.gz
fi

# Backup the logical volumes
backup_lvs

# Remove lock file
rm $LOCKFILE
