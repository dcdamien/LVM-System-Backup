#!/bin/bash
#
# Author: MrCrankHank
#

# Define default vars
start=`date +%s`
LOCKFILE=/var/run/lvm_system_backup.lock
NAGIOS_LOG=/var/log/lvm_system_backup_nagios_log
LVS=/tmp/lvs
RED='\e[0;31m'
NC='\e[0m'
ORANGE='\e[0;33m'
GREEN='\e[0;32m'
VERBOSE=0

# Define verbose function
function log_verbose() {
	if [[ $VERBOSE -eq 1 ]]; then
		echo -e "$@"
	fi
}

function log_error() {
	>&2 echo -e "$@"
}

# Abort if lockfile is found
if [ -f $LOCKFILE ]; then
	log_error "${RED}Error: ${NC}Backup is already running!"
	exit 1
fi

# Look for config in /etc/default
if [ -f /etc/default/lvm_system_backup_config ]; then
	. /etc/default/lvm_system_backup_config
	log_verbose "${ORANGE}Verbose: ${NC}Found the config file under /etc/default/lvm_system_backup_config"
	if ! [ -z $1 ]; then
		if [ $1 == '/etc/default/lvm_system_backup_config' ]; then
			log_verbose "${ORANGE}Verbose: ${NC}$1 is the default location. You don't have to specify this"
		else
			if [ -f $1 ]; then
				log_verbose "${ORANGE}Verbose: ${NC}Ignoring file at ${1}, because config file was found at default location"
			else
				log_verbose "${ORANGE}Verbose: ${NC}Ignoring file at ${1}, because it wasn't found. I will use the default file at /etc/default/lvm_system_backup_config"
			fi
		fi
	fi
else
	if [ -z $1 ]; then
		log_error "${RED}Error: ${NC}Can't find the config file at default location"
		log_error "${RED}Error: ${NC}Please specify one as first parameter"
		exit 1
	fi

	if ! [ -f $1 ]; then
		log_error "${RED}Error: ${NC}Can't find config file at $1"
		log_error "${RED}Error: ${NC}Please check the path and come back"
		exit 1
	else
		. $1
		log_verbose "${ORANGE}Verbose: ${NC}The location of the config file is in the first parameter. Location: $1"
	fi

	log_verbose "${ORANGE}Verbose: ${NC}Couldn't find the config file neither at the default path nor as the first parameter"
fi

# Check if lvdisplay is found
log_verbose "${ORANGE}Verbose: ${NC}Checking if lvdisplay is installed"
LVDISPLAY=`which lvdisplay`
if [ -z $LVDISPLAY ]; then
	log_error "${RED}Error: ${NC}Couldn't find lvdisplay"
	log_error "${RED}Error: ${NC}Are you sure your system is using lvm?"
	exit 1
else
	log_verbose "${ORANGE}Verbose: ${NC}lvdisplay found at $LVDISPLAY"
fi

# Get hostname
if [ -z $hostname ]; then
	if [ -f /etc/hostname ]; then
		hostname=$(</etc/hostname)
		log_verbose "${ORANGE}Verbose: ${NC}Reading hostname from /etc/hostname"
		log_verbose "${ORANGE}Verbose: ${NC}Hostname: $hostname"
	elif [ -f /bin/hostname ]; then
		hostname=$(/bin/hostname)
		log_verbose "${ORANGE}Verbose: ${NC}Getting hostname via /bin/hostname because /etc/hostname is missing"
		log_verbose "${ORANGE}Verbose: ${NC}Hostname: $hostname"
	else
		log_error "${RED}Error: ${NC}Can't find hostname"
		log_error "${RED}Error: ${NC}Please specify one via the config file"
		exit 1
	fi
fi

# Check if $BACKUP_BOOT var is set to 0/1
log_verbose "${ORANGE}Verbose: ${NC}Checking if the BACKUP_BOOT option is configured"

if [ -z $BACKUP_BOOT ]; then
	log_error "${RED}Error: ${NC}BACKUP_BOOT is not configured!"
	log_error "${RED}Error: ${NC}Please check the config file!"
	exit 1
fi

# Check if all vars from the config file are configured
log_verbose "${ORANGE}Verbose: ${NC}Checking if the BACKUP_BOOT option is enabled"

if [ $BACKUP_BOOT == 1 ]; then
		log_verbose "${ORANGE}Verbose: ${NC}BACKUP_BOOT is enabled"
		log_verbose "${ORANGE}Verbose: ${NC}Checking if all necessary vars are configured"

	if [[ -z "$VG_NAME" || -z "$DIR" || -z "$HOST" || -z "$USER" || -z "$DISK" || -z "$BOOT" ]]; then
		log_error "${RED}Error: ${NC}Important vars are missing!"
		log_error "${RED}Error: ${NC}Please check the config file!"
		exit 1
	fi
else
	log_verbose "${ORANGE}Verbose: ${NC}BACKUP_BOOT is disabled"
	log_verbose "${ORANGE}Verbose: ${NC}Checking if all necessary vars are configured"

	if [[ -z "$VG_NAME" || -z "$DIR" || -z "$HOST" || -z "$USER" ]]; then
		log_error "${RED}Error: ${NC}Important vars are missing!"
		log_error "${RED}Error: ${NC}Please check the config file!"
		exit 1
	fi
fi

# Check if the specified volume group is there
log_verbose "${ORANGE}Verbose: ${NC}Checking if the volume group $VG_NAME exists"

if ! [ -d /dev/$VG_NAME ]; then
	log_error "${RED}Error: ${NC}VG $VG_NAME not found!"
	exit 1
fi

# Checks for the backup boot feature
if [ $BACKUP_BOOT == 1 ]; then
	log_verbose "${ORANGE}Verbose: ${NC}Checking if the disk $DISK exists"

	if ! [ -b $DISK ]; then
		log_error "${RED}Error: ${NC}Disk $DISK not found!"
		exit 1
	fi

	log_verbose "${ORANGE}Verbose: ${NC}Checking if the boot disk $BOOT exists"

	if ! [ -b $BOOT ]; then
		log_error "${RED}Error: ${NC}Boot Disk $BOOT not found!"
		exit 1
	fi

	log_verbose "${ORANGE}Verbose: ${NC}Checking if the boot disk $BOOT is mounted on /boot"

	MOUNT=$(mount | grep /boot | grep -o $BOOT)

	if [ -z $MOUNT ]; then
		log_error "${RED}Error: ${NC}Boot disk $BOOT is not mounted on /boot"
		exit 1
	fi
fi

# Check if there is enough free space in the specified volume group to create a snapshot
log_verbose "${ORANGE}Verbose: ${NC}Checking if there is enough free space in the VG $VG_NAME to create a $SIZE snapshot"

SIZE_SNAPSHOT=$(echo $SIZE | sed -e 's/g//g' | sed -e 's/,/./g' | sed -e 's/G//g')
SIZE_FREE=$(lvs /dev/$VG_NAME -o vg_free | tail -1 | tr -d ' ' | sed -e 's/g//g' | sed -e 's/,/./g')
SIZE_OUT=$(bc <<< "${SIZE_FREE}-$SIZE_SNAPSHOT")
CHECK_SIZE=$(echo $SIZE | grep -c -)
SIZE_OUT=$(echo ${SIZE}G | sed -e 's/-//g')

if ! [ $CHECK_SIZE == 0 ]; then
	log_error "${RED}Error: ${NC}Not enough free space in VG $VG to create a snapshot"
	log_error "${RED}Error: ${NC}Need at least $SIZE_OUT space more"
	exit 1
fi

# Check if the excluded logical volumes are existing
if ! [ ${#LV_EXCLUDE[@]} -eq 0 ]; then
	log_verbose "${ORANGE}Verbose: ${NC}Checking if excluded LVs are existing"

	COUNTER=0
	while [ $COUNTER -lt ${#LV_EXCLUDE[@]} ]; do
        	if ! [ -b /dev/$VG_NAME/${LV_EXCLUDE[$COUNTER]} ]; then
        	       log_error "${RED}Error: ${NC}Excluded LV ${LV_EXCLUDE[$COUNTER]} doesn't exist"
        	       exit 1
	     fi
	       let COUNTER=COUNTER+1
	done
fi

# Create dir var with subfolders
datum=`date +%m/%d/%y`
DIR_DATE=`date +%m-%d-%y`
time=`date +"%T"`
DIR=$DIR/$hostname/$DIR_DATE

# Create lock file
log_verbose "${ORANGE}Verbose: ${NC}Creating lock file. Things are getting pretty serious"

touch $LOCKFILE

# Create list with logical volumes
log_verbose "${ORANGE}Verbose: ${NC}Creating list $LVS with all logical volumes in VG $VG_NAME"

lvdisplay $VG_NAME | grep -e "LV Name" | tr -d ' ' | sed -e 's/LVName//g' > $LVS

if [ $? -ne 0 ]; then
	log_error "${RED}Error: ${NC}Couldn't create the list with logical volumes"
	exit 1
fi

# Exclude logical volumes
log_verbose "${ORANGE}Verbose: ${NC}Checking if there are excluded volumes defined"
if ! [ ${#LV_EXCLUDE[@]} -eq 0 ]; then
	log_verbose "${ORANGE}Verbose: ${NC}Deleting all excluded logical volumes from the file $LVS"
	log_verbose "${ORANGE}Verbose: ${NC}Excluded volume/s is/are: ${LV_EXCLUDE[@]}"
        COUNTER=0
        while [ $COUNTER -lt ${#LV_EXCLUDE[@]} ]; do
                sed -i "/${LV_EXCLUDE[$COUNTER]}/d" $LVS
                let COUNTER=COUNTER+1
        done
else
	log_verbose "${ORANGE}Verbose: ${NC}No volumes to exclude!"
fi

# Modified code from the offical samba_backup script in source4/scripting/bin/samba_backup by Matthieu Patou
function samba_backup {
	log_verbose "${ORANGE}Verbose: ${NC}Checking if tdbbackkup is there"
	TDBBACKUP=`which tdbbackup`
	if [ -z $TDBBACKUP ]; then
		log_error "${RED}Error: ${NC}Cannot find tddbackup"
		log_error "${RED}Error: ${NC}Please check if you installed samba correctly"
		exit 1
	else
		log_verbose "${ORANGE}Verbose: ${NC}tdbbackup is at $TDBBACKUP"
	fi
	
	if [ -d /tmp/samba ]; then
		log_error "${RED}Error: ${NC}/tmp/samba folder already exists"
		log_error "${RED}Error: ${NC}Please delete it and start the script again"
	else
		mkdir /tmp/samba
	fi
	
	log_verbose "${ORANGE}Verbose: ${NC}Creating backup of samba files"
	if ! [ ${#SAMBA_DIRS[@]} -eq 0 ]; then
		COUNTER=0
		while [ $COUNTER -lt ${#SAMBA_DIRS[@]} ]; do
			if [[ ${SAMBA_DIRS[$COUNTER]} == *private* ]]; then
				rm "${SAMBA_DIRS[$COUNTER]}/*.ldb.bak" &>/dev/null
				for ldb in ${SAMBA_DIRS[$COUNTER]}; do
					tdbbackup $ldb/*.ldb
					if [ $? -ne 0 ]; then
						log_error "${RED}Error: ${NC}Could not backup $ldb"
						exit 1
					fi
				done
				
				log_verbose "${ORANGE}Verbose: ${NC}Copy ${SAMBA_DIRS[$COUNTER]} to /tmp/samba"
				rsync -avzq --exclude *.ldb ${SAMBA_DIRS[$COUNTER]} /tmp/samba &>/dev/null
				if [ $? -ne 0 ]; then
					log_error "${RED}Error: ${NC}Couldn't rsync ${SAMBA_DIRS[$COUNTER]} to /tmp/samba"
					exit 1
				fi
				rm "${SAMBA_DIRS[$COUNTER]}/*.ldb.bak" &>/dev/null
			else
				log_verbose "${ORANGE}Verbose: ${NC}Copy ${SAMBA_DIRS[$COUNTER]} to /tmp/samba"
				rsync -avzq ${SAMBA_DIRS[$COUNTER]} /tmp/samba &>/dev/null
				if [ $? -ne 0 ]; then
					log_error "${RED}Error: ${NC}Couldn't rsync ${SAMBA_DIRS[$COUNTER]} to /tmp/samba"
					exit 1
				fi
			fi
			let COUNTER=COUNTER+1
		done
		log_verbose "${ORANGE}Verbose: ${NC}Compressing /tmp/samba to /tmp/samba4.tar.gz"
		tar czf /tmp/samba4.tar.gz /tmp/samba &>/dev/null
		if [ $? -ne 0 ]; then
			log_error "${RED}Error: ${NC}Couldn't compress /tmp/samba to /tmp/samba4.tar.gz"
		fi
				
		log_verbose "${ORANGE}Verbose: ${NC}Sending /tmp/samba4.tar.gz to $HOST"
		scp /tmp/samba4.tar.gz ${USER}@$HOST:$DIR/samba4.tar.gz &>/dev/null
		if [ $? -ne 0 ]; then
			log_error "${RED}Error: ${NC}Error while sending /tmp/samba4.tar.gz to $HOST"
		fi
			
		log_verbose "${ORANGE}Verbose: ${NC}Removing /tmp/samba4.tar.gz"
		if [ -f /tmp/samba4.tar.gz ]; then
			rm /tmp/samba4.tar.gz &> /dev/null
		fi
			
		log_verbose "${ORANGE}Verbose: ${NC}Removing /tmp/samba"
		if [ -d /tmp/samba ]; then
			rm -r /tmp/samba &> /dev/null
		fi
	fi
}

# Exit trap to delete the snapshots and the lockfile
function finish {
	log_verbose "${ORANGE}Verbose: ${NC}Cleaning up..."

        while read lv; do
                if [ -e /dev/$VG_NAME/${lv}_snap ]; then
                        lvremove -f /dev/$VG_NAME/${lv}_snap &> /dev/null
			if [ $? -ne 0 ]; then
				log_error "${RED}Error: ${NC}Couldn't remove ${lv}_snap"
				exit 1
			fi
                fi
        done < $LVS

        if [ -f $LOCKFILE ]; then
		rm $LOCKFILE
	fi
	
	if [ -f /tmp/samba4.tar.gz ]; then
		rm /tmp/samba4.tar.gz &> /dev/null
	fi
	
	if [ -d /tmp/samba ]; then
		rm -r /tmp/samba &> /dev/null
	fi

	log_verbose "${ORANGE}Verbose: ${NC}Done"
}
trap finish EXIT

function check_ssh {
	nc -z -w5 $HOST 22 &> /dev/null
	
	if [ $? -ne 0 ]; then
		log_error "${RED}Error: ${NC}Cannot connect to host $HOST via port 22"
		exit 1
	fi
	
	if ! [ -d ~/.ssh ]; then
		log_verbose "${ORANGE}Verbose: ${NC}Can't find ~/.ssh directory. No public key authentication possible."
		log_verbose "${ORANGE}Verbose: ${NC}You need to setup public authentication with the server that will store your backups."
		log_verbose "${ORANGE}Verbose: ${NC}For testing purpose you can also manually type a password."
	fi
	
	if ! [ -f ~/.ssh/id_rsa ]; then
		log_verbose "${ORANGE}Verbose: ${NC}Can't find the privat key in your ~/.ssh directory. No public key authentication possible."
		log_verbose "${ORANGE}Verbose: ${NC}You need to setup public authentication with the server that will store your backups."
		log_verbose "${ORANGE}Verbose: ${NC}For testing purpose you can also manually type a password."
	elif [ -f ~/.ssh/id_rsa ]; then
		log_verbose "${ORANGE}Verbose: ${NC}Checking if key permissions is set to 600"
		TEST=$(stat --format=%a ~/.ssh/id_rsa)
		if [ $TEST != 600 ]; then
			log_verbose "${ORANGE}Verbose: ${NC}Your key permission is $TEST"
			log_verbose "${ORANGE}Verbose: ${NC}Please set ~/.ssh/id_rsa permissions to 600"
			log_verbose "${ORANGE}Verbose: ${NC}I will continue anyway, but ssh won't connect without password!"
		fi
	fi
}

function backup_layout {
	# Backup partition table
	log_verbose "${ORANGE}Verbose: ${NC}Backing up partiton table to /tmp/part_table"

	if [ -d /tmp ]; then
		if [ -f /tmp/.test ]; then
			rm /tmp/.test &> /dev/null
		fi
		touch /tmp/.test &> /dev/null
		if [ $? -ne 0 ]; then
			log_error "${RED}Error: ${NC}/tmp not writeable"
			exit 1
		fi
	else
		log_error "${RED}Error: ${NC}/tmp doesn't exist"
		exit 1
	fi

	sfdisk --quiet -d $DISK > /tmp/part_table

	log_verbose "${ORANGE}Verbose: ${NC}Sending partition table backup to $HOST:$DIR"

	if [ -f /tmp/part_table ]; then
		scp /tmp/part_table $USER@$HOST:$DIR/part_table &> /dev/null

		if [ $? -ne 0 ]; then
			log_error "${RED}Error: ${NC}Cannot login or connect to $HOST"
			exit 1
		fi
	else
		log_error "${RED}Error: ${NC}Can't copy /tmp/part_table to $HOST. File doens't exist"
		exit 1
	fi

	log_verbose "${ORANGE}Verbose: ${NC}Deleting partition table in /tmp/part_table"

	rm /tmp/part_table

	# Backup lvm structure
	log_verbose "${ORANGE}Verbose: ${NC}Backing up lvm structure to /tmp/lvm_structure"

	vgcfgbackup -f /tmp/lvm_structure /dev/$VG_NAME &> /dev/null

	if [ $? -ne 0 ]; then
		log_error "${RED}Error: ${NC}Couldn't backup the lvm structure of volume group $VG_NAME"
		exit 1
	fi

	log_verbose "${ORANGE}Verbose: ${NC}Sending lvm structure to $HOST:$DIR"

	if [ -f /tmp/lvm_structure ]; then
		scp /tmp/lvm_structure ${USER}@$HOST:$DIR/lvm_structure &> /dev/null

		if [ $? -ne 0 ]; then
			log_error "${RED}Error: ${NC}Cannot login or connect to $HOST"
			exit 1
		fi
	else
		log_error "${RED}Error: ${NC}Can't copy /tmp/lvm_structure to $HOST. File doens't exist"
		exit 1
	fi

	log_verbose "${ORANGE}Verbose: ${NC}Deleting lvm structure in /tmp/lvm_structure"

	rm /tmp/lvm_structure
}

function backup_lvs {
	# Create a snapshot of every volume and copy it using dd
	log_verbose "${ORANGE}Verbose: ${NC}Starting loop for every volume in $LVS"

	while read lv; do
		# Wrapper to silence output
		function copy_lv {
			dd if=/dev/$VG_NAME/${lv}_snap | gzip -1 - | ssh ${USER}@$HOST dd of=$DIR/${lv}.img.gz
		}

		log_verbose "${ORANGE}Verbose: ${NC}Creating a $SIZE snapshot named ${lv}_snap of LV ${lv} in VG $VG_NAME"
		lvcreate --snapshot -L $SIZE -n ${lv}_snap /dev/$VG_NAME/$lv &> /dev/null

		if [ $? -ne 0 ]; then
			log_error "${RED}Error: ${NC}Couldn't create a $SIZE snapshot named ${lv}_snap of LV ${lv} in VG $VG_NAME"
			exit 1
		fi
		log_verbose "${ORANGE}Verbose: ${NC}Copy the compressed volume ${lv} via dd to $HOST"
		copy_lv &> /dev/null

		if [ $? -ne 0 ]; then
			log_error "${RED}Error: ${NC}Couldn't copy the compressed volume ${lv} to $HOST"
			exit 1
		fi
		log_verbose "${ORANGE}Verbose: ${NC}Removing the snapshot ${lv}_snap"
		lvremove -f /dev/$VG_NAME/${lv}_snap &> /dev/null

		if [ $? -ne 0 ]; then
			log_error "${RED}Error: ${NC}Couldn't delete the snapshot named ${lv}_snap of lv ${lv}"
			exit 1
		fi
	done < $LVS
}


function backup_boot {
	# Wrapper to silence output
	function copy_boot {
		dd if=$BOOT | gzip -1 - | ssh ${USER}@$HOST dd of=$DIR/boot.img.gz
	}

	function copy_mbr {
		dd if=$DISK bs=512 count=1 | gzip -1 - | ssh ${USER}@$HOST dd of=$DIR/mbr.img.gz
	}

	# Create image of /boot
        log_verbose "${ORANGE}Verbose: ${NC}Copy $BOOT to $HOST via dd"
	copy_boot &> /dev/null

        if [ $? -ne 0 ]; then
                log_error "${RED}Error: ${NC}Couldn't copy the boot disk $BOOT to $HOST"
                exit 1
        fi

        # Create image of mbr with grub
        log_verbose "${ORANGE}Verbose: ${NC}Create a 512 byte image of the mbr"
	copy_mbr &> /dev/null

        if [ $? -ne 0 ]; then
                log_error "${RED}Error: ${NC}Couldn't create an image of the mbr"
        fi

}

# Checking server connection
log_verbose "${ORANGE}Verbose: ${NC}Checking if I can connect to $HOST"
check_ssh

# Create remote backup dir
log_verbose "${ORANGE}Verbose: ${NC}Creating remote dir $DIR to store the backups on $HOST"
ssh ${USER}@$HOST mkdir -p $DIR &>/dev/null
if [ $? -ne 0 ]; then
	log_error "${RED}Error: ${NC}Couldn't create the remote dir $DIR to store the backups"
	exit 1
fi

# Backup lvm and mbr layout
log_verbose "${ORANGE}Verbose: ${NC}Starting the backups of lvm and mbr layout..."
backup_layout

if [ $BACKUP_BOOT == 1 ]; then
	backup_boot
fi

# Backup the logical volumes
backup_lvs

# Remove lock file
log_verbose "${ORANGE}Verbose: ${NC}Removing the lock file, if exists"
if [ -f $LOCKFILE ]; then
	rm $LOCKFILE
fi

# Calculate runtime
end=`date +%s`
log_verbose "${ORANGE}Verbose: ${NC}Execution took $((end-start)) seconds"

# Write nagios log
if ! [ -z $NAGIOS ]; then
	if [ $NAGIOS == 1 ]; then
		log_verbose "${ORANGE}Verbose: ${NC}Creating log file for nagios plugin"

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
