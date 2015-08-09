#!/bin/bash
#
# Author: MrCrankHank
#

# Define default vars
start=`date +%s`
LOCKFILE=/var/run/lvm_system_backup.lock
NAGIOS_LOG=/var/log/lvm_system_backup_nagios_log
MYSQL_DB=/tmp/mysql_db
NC='\e[0m'				# Message
RED='\e[0;31m'			# Error
ORANGE='\e[0;33m'		# Warning
GREEN='\e[0;32m'		# Success
MAGENTA='\e[95m'		# Verbose
BLUE='\e[34m'			# Message
VERBOSE=0
BACKUP_BOOT=0
BACKUP_VG=0
BACKUP_SAMBA=0
BACKUP_MYSQL=0
NAGIOS=0
DELETE_OLD_DATA=0
IGNORE_DIR=0
UNSECURE_TRANSMISSION=0
LOCAL_BACKUP=0

# Define log functions
function log_verbose() {
	if [[ $VERBOSE -eq 1 ]]; then
		echo -e "${MAGENTA}Verbose: ${NC}$@"
	fi
}

function log_error() {
	>&2 echo -e "${RED}Error: ${NC}$@"
}

function log_warning() {
	echo -e "${ORANGE}Warning: ${NC}$@"
}

function log_success() {
	echo -e "${GREEN}Success: ${NC}$@"
}

function log_message() {
	echo -e "${BLUE}Message: ${NC}$@"
}

# Abort if lockfile is found
if [ -f $LOCKFILE ]; then
	log_error "Backup is already running!"
	exit 1
fi

# Look for config in /etc/default
if [ -f /etc/default/lvm_system_backup_config ]; then
	. /etc/default/lvm_system_backup_config
	log_verbose "Found the config file under /etc/default/lvm_system_backup_config"
	if ! [ -z $1 ]; then
		if [ $1 == '/etc/default/lvm_system_backup_config' ]; then
			log_verbose "$1 is the default location. You don't have to specify this"
		else
			if [ -f $1 ]; then
				log_verbose "Ignoring file at ${1}, because config file was found at default location"
			else
				log_verbose "Ignoring file at ${1}, because it wasn't found. I will use the default file at /etc/default/lvm_system_backup_config"
			fi
		fi
	fi
else
	if [ -z $1 ]; then
		log_error "Can't find the config file at default location"
		log_error "Please specify one as first parameter"
		exit 1
	fi

	if ! [ -f $1 ]; then
		log_error "Can't find config file at $1"
		log_error "Please check the path and come back"
		exit 1
	else
		. $1
		log_verbose "The location of the config file is in the first parameter. Location: $1"
	fi
fi

# Check if all vars from the config file are configured
log_verbose "Checking if all needed vars are configured"
# Get hostname
if [ -z $hostname ]; then
	if [ -f /etc/hostname ]; then
		hostname=$(</etc/hostname)
		log_verbose "Reading hostname from /etc/hostname"
		log_verbose "Hostname: $hostname"
	elif [ -f /bin/hostname ]; then
		hostname=$(/bin/hostname)
		log_verbose "Getting hostname via /bin/hostname because /etc/hostname is missing"
		log_verbose "Hostname: $hostname"
	else
		log_error "Can't find hostname"
		log_error "Please specify one via the config file"
		exit 1
	fi
fi

log_verbose "Checking if there are backup features enabled"
if [[ $BACKUP_BOOT == 0 && $BACKUP_VG == 0 && $BACKUP_SAMBA == 0 && $BACKUP_MYSQL == 0 ]]; then
	log_error "You haven't configured any backup features!"
	exit 1
fi

log_verbose "Checking if there are conflicting features enabled"
if [[ $UNSECURE_TRANSMISSION == 1 && $LOCAL_BACKUP == 1 ]]; then
	log_error "You can't enable UNSECURE_TRANSMISSION and LOCAL_BACKUP!"
	exit 1
fi	
	
# Check common vars
if [[ -z "$DIR" || -z "$HOST" ]]; then
	log_error "Important vars are missing!"
	log_error "Please check the config file!"
	exit 1
fi

if ! [ $LOCAL_BACKUP == 1 ]; then
	if [ -z $USER ]; then
		log_error "Please set a user in your config file!"
		exit 1
	fi
fi	

# Check BACKUP_BOOT
if [ $BACKUP_BOOT == 1 ]; then
	if [[ -z $DISK || -z $BOOT ]]; then
		log_error "The vars for the BACKUP_BOOT feature are invalid"
		log_error "Please check them and come back"
		exit 1
	fi
fi
	
# Check BACKUP_VG
if [[ $BACKUP_VG == 1 ]]; then
	if [[ ${#VG_NAME[@]} -eq 0 ]]; then
		log_error "The vars for the BACKUP_VG feature are invalid"
		log_error "Please check them and come back"
		exit 1
	fi
fi

# Check BACKUP_SAMBA
if [[ $BACKUP_SAMBA == 1 ]]; then
	if [ ${#SAMBA_DIRS[@]} -eq 0 ]; then
		log_error "The array SAMBA_DIRS has no fields"
		log_error "This array must be configured with the paths to your samba data"
		log_error "Please check it and come back"
		exit 1
	fi
fi

# Check BACKUP_MYSQL
if [[ $BACKUP_MYSQL == 1 ]]; then
	if [[ -z $MYSQL_USER || -z $MYSQL_PASSWORD ]]; then
		log_error "The vars for the BACKUP_MYSQL feature are invalid"
		log_error "Please check them and come back"
		exit 1
	fi
fi

# Check DELETE_OLD_DATA
if [ $DELETE_OLD_DATA == 1 ]; then
	if [ -z $DAYS_OLD ]; then
		log_error "The vars for the DELETE_OLD_DATA feature are invalid"
		log_error "Please check them and come back"
		exit 1
	fi
fi

# Check UNSECURE_TRANSMISSION
if [ $UNSECURE_TRANSMISSION == 1 ]; then
	if [ -z $PORT ]; then
		log_error "The vars for the UNSECURE_TRANSMISSION feature are invalid"
		log_error "Please check them and come back"
		exit 1
	fi
fi

# Checking enabled backup features
log_message "Checking enabled features"
log_verbose "Checking if the BACKUP_BOOT feature is enabled"
if ! [ -z $BACKUP_BOOT ]; then
	if [ $BACKUP_BOOT == 1 ]; then
		log_message "BACKUP_BOOT feature is enabled"
	else
		log_message "BACKUP_BOOT feature is disabled"
	fi
fi

log_verbose "Checking if the BACKUP_VG feature is enabled"
if ! [ -z $BACKUP_VG ]; then
	if [ $BACKUP_VG == 1 ]; then
		log_message "BACKUP_VG feature is enabled"
	else
		log_message "BACKUP_VG feature is disabled"
	fi
fi

log_verbose "Checking if the NAGIOS feature is enabled"
if ! [ -z $NAGIOS ]; then
	if [ $NAGIOS == 1 ]; then
		log_message "NAGIOS feature is enabled"
	else
		log_message "NAGIOS feature is disabled"
	fi
fi

log_verbose "Checking if the BACKUP_SAMBA feature is enabled"
if ! [ -z $BACKUP_SAMBA ]; then
	if [ $BACKUP_SAMBA == 1 ]; then
		log_message "BACKUP_SAMBA feature is enabled"
	else
		log_message "BACKUP_SAMBA feature is disabled"
	fi
fi

log_verbose "Checking if the BACKUP_MYSQL feature is enabled"
if ! [ -z $BACKUP_MYSQL ]; then
	if [ $BACKUP_MYSQL == 1 ]; then
		log_message "BACKUP_MYSQL feature is enabled"
	else
		log_message "BACKUP_MYSQL feature is disabled"
	fi
fi

log_verbose "Checking if the DELETE_OLD_DATA feature is enabled"
if ! [ -z $DELETE_OLD_DATA ]; then
	if [ $DELETE_OLD_DATA == 1 ]; then
		log_message "DELETE_OLD_DATA feature is enabled"
	else
		log_message "DELETE_OLD_DATA feature is disabled"
	fi
fi

log_verbose "Checking if the UNSECURE_TRANSMISSION feature is enabled"
if ! [ -z $UNSECURE_TRANSMISSION ]; then
	if [ $UNSECURE_TRANSMISSION == 1 ]; then
		log_message "UNSECURE_TRANSMISSION feature is enabled"
	else
		log_message "UNSECURE_TRANSMISSION feature is disabled"
	fi
fi	

log_verbose "Checking if the LOCAL_BACKUP feature is enabled"
if ! [ -z $LOCAL_BACKUP ]; then
	if [ $LOCAL_BACKUP == 1 ]; then
		log_message "LOCAL_BACKUP feature is enabled"
		# Set HOST var to value indicating that backup is saved to local dir instead remote
		HOST=$DIR" (LOCAL_BACKUP)"
	else
		log_message "LOCAL_BACKUP feature is disabled"
	fi
fi	


# Create lock file
log_verbose "Creating lock file. Things are getting pretty serious"
touch $LOCKFILE

# Create dir var with subfolders
datum=`date +%m/%d/%y`
DIR_DATE=`date +%m-%d-%y`
time=`date +"%T"`
DIR_FULL=$DIR/$hostname/$DIR_DATE

function BACKUP_BOOT {
	# Checks for the backup boot feature
	if [ $BACKUP_BOOT == 1 ]; then
		log_verbose "Checking if the disk $DISK exists"

		if ! [ -b $DISK ]; then
			log_error "Disk $DISK not found!"
			exit 1
		fi

		log_verbose "Checking if the boot disk $BOOT exists"

		if ! [ -b $BOOT ]; then
			log_error "Boot Disk $BOOT not found!"
			exit 1
		fi

		log_verbose "Checking if the boot disk $BOOT is mounted on /boot"

		MOUNT=$(mount | grep /boot | grep -o $BOOT)

		if [ -z $MOUNT ]; then
			log_error "Boot disk $BOOT is not mounted on /boot"
			exit 1
		fi
	fi
	
	# Wrapper to silence output
	function copy_boot {
		if [ $LOCAL_BACKUP == 1 ]; then
			dd if=$BOOT | gzip -1 - | dd of=$DIR_FULL/boot.img.gz
		elif [ $UNSECURE_TRANSMISSION == 1 ]; then
			ssh ${USER}@$HOST "nohup netcat -l -p $PORT | dd of=$DIR_FULL/boot.img.gz &"
			dd if=$BOOT | gzip -1 - | netcat -q 1 $HOST $PORT
		else
			dd if=$BOOT | gzip -1 - | ssh ${USER}@$HOST dd of=$DIR_FULL/boot.img.gz
		fi
	}

	function copy_mbr {
		if [ $LOCAL_BACKUP == 1 ]; then
			dd if=$DISK bs=512 count=1 | gzip -1 - | dd of=$DIR_FULL/mbr.img.gz
		elif [ $UNSECURE_TRANSMISSION == 1 ]; then
			ssh ${USER}@$HOST "nohup netcat -l -p $PORT | dd of=$DIR_FULL/mbr.img.gz &"
			dd if=$DISK bs=512 count=1 | gzip -1 - | netcat -q 1 $HOST $PORT
		else
			dd if=$DISK bs=512 count=1 | gzip -1 - | ssh ${USER}@$HOST dd of=$DIR_FULL/mbr.img.gz
		fi	
	}

	# Remount /boot read only
	log_verbose "Remounting boot partition $BOOT ro"
	mount -r -o remount $BOOT
	if [ $? -ne 0 ]; then
		log_warning "Couldn't remount $BOOT read only"
		log_warning "Low risk, i keep going..."
    	fi

	# Create image of /boot
    	log_verbose "Copy $BOOT to $HOST via dd"
		copy_boot &> /dev/null
    	if [ $? -ne 0 ]; then
		log_error "Couldn't copy the boot disk $BOOT to $HOST"
        	exit 1
    	fi

    	# Create image of mbr with grub
    	log_verbose "Create a 512 byte image of the mbr"
		copy_mbr &> /dev/null
    	if [ $? -ne 0 ]; then
        	log_error "Couldn't create an image of the mbr"
        	exit 1
    	fi
    	
    	# Remount /boot read write
    	log_verbose "Remounting boot partition $BOOT rw"
    	mount -o remount,rw $BOOT
    	if [ $? -ne 0 ]; then
		log_warning "Couldn't remount $BOOT read write again"
		log_warning "You should check what went wrong"
    	fi
}

function BACKUP_VG {
	# Check if lvdisplay is found
	log_verbose "Checking if lvdisplay is installed"
	LVDISPLAY=`which lvdisplay`
	if [ -z $LVDISPLAY ]; then
		log_error "Couldn't find lvdisplay"
		log_error "Are you sure your system is using lvm?"
		exit 1
	else
		log_verbose "lvdisplay found at $LVDISPLAY"
	fi

	# Check if lvs is found
	log_verbose "Checking if lvs is installed"
	LVS_BIN=`which lvs`
	if [ -z $LVS_BIN ]; then
		log_error "Couldn't find lvs"
		log_error "Are you sure your system is using lvm?"
		exit 1
	else
		log_verbose "lvs found at $LVS_BIN"
	fi

	COUNTER2=0
	while [ $COUNTER2 -lt ${#VG_NAME[@]} ]; do
		LVS=/tmp/lvs_${VG_NAME[$COUNTER2]}
		# Check if the specified volume group is there
		log_verbose "Checking if the volume group $VG_NAME exists"

		if ! [ -d /dev/${VG_NAME[$COUNTER2]} ]; then
			log_error "VG $VG_NAME not found!"
			exit 1
		fi
		# Check if there is enough free space in the specified volume group to create a snapshot
		log_verbose "Checking if there is enough free space in the VG ${VG_NAME[$COUNTER2]} to create a ${SIZE[$COUNTER2]} snapshot"
				
		SIZE_SNAPSHOT=$(echo $SIZE | sed -e 's/g//g' | sed -e 's/,/./g' | sed -e 's/G//g')
		SIZE_FREE=$(lvs /dev/$VG_NAME -o vg_free | tail -1 | tr -d ' ' | sed -e 's/g//g' | sed -e 's/,/./g')
		SIZE_OUT=$(bc <<< "${SIZE_FREE}-$SIZE_SNAPSHOT")
		CHECK_SIZE=$(echo $SIZE | grep -c -)
		SIZE_OUT=$(echo ${SIZE}G | sed -e 's/-//g')

		if ! [ $CHECK_SIZE == 0 ]; then
			log_error "Not enough free space in VG ${VG_NAME[$COUNTER2]} to create a snapshot"
			log_error "Need at least $SIZE_OUT space more"
			exit 1
		fi

		# Check if the excluded logical volumes are existing
		if ! [ ${#LV_EXCLUDE[@]} -eq 0 ]; then
			log_verbose "Checking if excluded LVs are existing"

			COUNTER=0
			while [ $COUNTER -lt ${#LV_EXCLUDE[@]} ]; do
				if ! [ -b /dev/${VG_NAME[$COUNTER2]}/${LV_EXCLUDE[$COUNTER]} ]; then
					log_warning "Excluded LV ${LV_EXCLUDE[$COUNTER]} doesn't exist in VG ${VG_NAME[$COUNTER2]}"
				fi
				let COUNTER=COUNTER+1
			done
		fi
		
		# Create list with logical volumes
		log_verbose "Creating list $LVS with all logical volumes in VG ${VG_NAME[$COUNTER2]}"

		# List all volumes excluding snapshots
		lvs -o lv_name ${VG_NAME[$COUNTER2]} --noheadings -S 'lv_attr!~[^s.*]' | sed -e 's/^[ \t]*//' > $LVS

		# lvdisplay ${VG_NAME[$COUNTER2]} | grep -e "LV Name" | tr -d ' ' | sed -e 's/LVName//g' > $LVS

		if [ $? -ne 0 ]; then
			log_error "Couldn't create the list with logical volumes"
			exit 1
		fi
		
		# Exclude logical volumes
		log_verbose "Checking if there are excluded volumes defined"
		if ! [ ${#LV_EXCLUDE[@]} -eq 0 ]; then
			log_verbose "Deleting all excluded logical volumes from the file $LVS"
			log_verbose "Excluded volume/s is/are: ${LV_EXCLUDE[@]}"
				COUNTER=0
				while [ $COUNTER -lt ${#LV_EXCLUDE[@]} ]; do
						sed -i "/${LV_EXCLUDE[$COUNTER]}/d" $LVS
						let COUNTER=COUNTER+1
				done
		else
			log_verbose "No volumes to exclude!"
		fi
		
		# Create remote backup dir with VG Name
		log_verbose "Creating directory $DIR_FULL/${VG_NAME[$COUNTER2]} on host $HOST"
		if [ $LOCAL_BACKUP == 1 ]; then
			mkdir -p $DIR_FULL/${VG_NAME[$COUNTER2]} &>/dev/null
		else	
			ssh ${USER}@$HOST mkdir -p $DIR_FULL/${VG_NAME[$COUNTER2]} &>/dev/null
		fi	
		if [ $? -ne 0 ]; then
			log_error "Couldn't create the remote dir $DIR_FULL/${VG_NAME[$COUNTER2]} to store the VG backups"
			exit 1
		fi
		
		# Create a snapshot of every volume and copy it using dd
		log_verbose "Starting loop for every volume in $LVS"

		while read lv; do
			# Wrapper to silence output
			function copy_lv {
				if [ $LOCAL_BACKUP == 1 ]; then
					dd if=/dev/${VG_NAME[$COUNTER2]}/${lv}$SNAPSHOT_SUFFIX | gzip -1 - | dd of=$DIR_FULL/${VG_NAME[$COUNTER2]}/${lv}.img.gz
				elif [ $UNSECURE_TRANSMISSION == 1 ]; then
					ssh -n ${USER}@$HOST "nohup netcat -l -p $PORT | dd of=$DIR_FULL/${VG_NAME[$COUNTER2]}/${lv}.img.gz &"
					dd if=/dev/${VG_NAME[$COUNTER2]}/${lv}$SNAPSHOT_SUFFIX | gzip -1 - | netcat -q 1 $HOST $PORT
					let PORT=$PORT+1
				else
					lz4 < /dev/${VG_NAME[$COUNTER2]}/${lv}$SNAPSHOT_SUFFIX | ssh ${USER}@$HOST "cat > $DIR_FULL/${VG_NAME[$COUNTER2]}/${lv}.img.lz4"
				fi
			}

			log_verbose "Creating a $SIZE snapshot named ${lv}$SNAPSHOT_SUFFIX of LV ${lv} in VG $VG_NAME"

			lvcreate --snapshot -L ${SIZE[$COUNTER2]} -n ${lv}$SNAPSHOT_SUFFIX /dev/${VG_NAME[$COUNTER2]}/$lv &> /dev/null

			if [ $? -ne 0 ]; then
				log_warning "Couldn't create a $SIZE snapshot named ${lv}$SNAPSHOT_SUFFIX of LV ${lv} in VG $VG_NAME, checking if snapshot already exist"

				if [ -b /dev/${VG_NAME[$COUNTER2]}/${lv}$SNAPSHOT_SUFFIX ]; then
					log_verbose "Snapshot named ${lv}$SNAPSHOT_SUFFIX already exist"
				else
					log_error "Snapshot named ${lv}$SNAPSHOT_SUFFIX not exist"
					exit 1
				fi
			fi

			log_verbose "Copy the compressed volume ${lv} via dd to $HOST"
			copy_lv &> /dev/null

			if [ $? -ne 0 ]; then
				log_error "Couldn't copy the compressed volume ${lv} to $HOST"
				exit 1
			fi
			log_verbose "Removing the snapshot ${lv}$SNAPSHOT_SUFFIX"
			lvremove -f /dev/${VG_NAME[$COUNTER2]}/${lv}$SNAPSHOT_SUFFIX &> /dev/null

			if [ $? -ne 0 ]; then
				log_error "Couldn't delete the snapshot named ${lv}$SNAPSHOT_SUFFIX of lv ${lv}"
				exit 1
			fi
		done < $LVS
		let COUNTER2=$COUNTER2+1
	done
}

# Modified code from the offical samba_backup script in source4/scripting/bin/samba_backup by Matthieu Patou
function BACKUP_SAMBA {
	log_verbose "Checking if rsync is installed"
	VRSYNC=`which rsync`
	if [ -z $VRSYNC ]; then
		log_error "Cannot find rsync"
		log_error "Please install rsync"
		exit 1
	else
		log_verbose "rsync is at $VRSYNC"
	fi
	
	
	log_verbose "Checking if tdbbackkup is there"
	TDBBACKUP=`which tdbbackup`
	if [ -z $TDBBACKUP ]; then
		log_error "Cannot find tdbbackup"
		log_error "Please check if you installed samba correctly"
		exit 1
	else
		log_verbose "tdbbackup is at $TDBBACKUP"
	fi
	
	if [ -d /tmp/samba ]; then
		log_error "/tmp/samba folder already exists"
		log_error "Please delete it and start the script again"
		exit 1
	else
		mkdir /tmp/samba
	fi
	
	log_verbose "Creating backup of samba files"
	if ! [ ${#SAMBA_DIRS[@]} -eq 0 ]; then
		COUNTER=0
		while [ $COUNTER -lt ${#SAMBA_DIRS[@]} ]; do
			if [[ ${SAMBA_DIRS[$COUNTER]} == *private* ]]; then
				rm ${SAMBA_DIRS[$COUNTER]}/*.ldb.bak &>/dev/null
				for ldb in ${SAMBA_DIRS[$COUNTER]}; do
					tdbbackup $ldb/*.ldb
					if [ $? -ne 0 ]; then
						log_error "Could not backup $ldb"
						exit 1
					fi
				done
				
				log_verbose "Copy ${SAMBA_DIRS[$COUNTER]} to /tmp/samba"
				mkdir -p /tmp/samba/${SAMBA_DIRS[$COUNTER]} &>/dev/null
				rsync -avzqR --exclude *.ldb ${SAMBA_DIRS[$COUNTER]} /tmp/samba
				if [ $? -ne 0 ]; then
					log_error "Couldn't rsync ${SAMBA_DIRS[$COUNTER]} to /tmp/samba"
					exit 1
				fi
				
				log_verbose "Deleting ldb.bak files from ${SAMBA_DIRS[$COUNTER]}"
				rm ${SAMBA_DIRS[$COUNTER]}/*.ldb.bak &>/dev/null
				if [ $? -ne 0 ]; then
					log_error "Deletion of ldb.bak files in ${SAMBA_DIRS[$COUNTER]} failed"
					exit 1
				fi
			else
				log_verbose "Copy ${SAMBA_DIRS[$COUNTER]} to /tmp/samba"
				mkdir -p /tmp/samba/${SAMBA_DIRS[$COUNTER]} &>/dev/null
				rsync -avzqR ${SAMBA_DIRS[$COUNTER]} /tmp/samba
				if [ $? -ne 0 ]; then
					log_error "Couldn't rsync ${SAMBA_DIRS[$COUNTER]} to /tmp/samba"
					exit 1
				fi
			fi
			let COUNTER=COUNTER+1
		done
		log_verbose "Compressing /tmp/samba to /tmp/samba4.tar.gz"
		tar czf /tmp/samba4.tar.gz /tmp/samba &>/dev/null
		if [ $? -ne 0 ]; then
			log_error "Couldn't compress /tmp/samba to /tmp/samba4.tar.gz"
			exit 1
		fi
				
		log_verbose "Sending /tmp/samba4.tar.gz to $HOST"
		
		if [ $LOCAL_BACKUP == 1 ]; then
			cp /tmp/samba4.tar.gz $DIR_FULL/samba4.tar.gz &>/dev/null
		else 	
			scp /tmp/samba4.tar.gz ${USER}@$HOST:$DIR_FULL/samba4.tar.gz &>/dev/null
		fi	
		if [ $? -ne 0 ]; then
			log_error "Error while sending /tmp/samba4.tar.gz to $HOST"
			exit 1
		fi
			
		log_verbose "Removing /tmp/samba4.tar.gz"
		if [ -f /tmp/samba4.tar.gz ]; then
			rm /tmp/samba4.tar.gz &> /dev/null
		fi
			
		log_verbose "Removing /tmp/samba"
		if [ -d /tmp/samba ]; then
			rm -r /tmp/samba &> /dev/null
		fi
	fi
}

function BACKUP_MYSQL {
	# Wrapper to silence output
	function dump {
		$MYSQLDUMP -u$MYSQL_USER -p"$MYSQL_PASSWORD" --complete-insert "$db" > /tmp/"$db".sql
	}

	# Check if mysql dump is installed
	MYSQLDUMP=`which mysqldump`
	if [ -z $MYSQLDUMP ]; then
		log_error "Cannot find mysqldump!"
	else
		log_verbose "MySQLDump was found at $MYSQLDUMP"
	fi

	log_verbose "Creating file /tmp/mysql_db with all databases"
	mysql -u$MYSQL_USER -p"$MYSQL_PASSWORD" -Bse 'show databases' > $MYSQL_DB

	if ! [ ${#MYSQL_EXCLUDE[@]} -eq 0 ]; then
		log_verbose "Removing excluded databases from /tmp/mysql_db"
		log_verbose "Excluded database/s is/are: ${MYSQL_EXCLUDE[@]}"

		COUNTER=0
		while [ $COUNTER -lt ${#MYSQL_EXCLUDE[@]} ]; do
			sed -i "/${MYSQL_EXCLUDE[$COUNTER]}/d" $MYSQL_DB
			let COUNTER=COUNTER+1
		done
	else
		log_verbose "No databases to exclude"
	fi

	while read db; do
		log_verbose "Creating backup of database $db"
		dump &>/dev/null
		if [ $? -ne 0 ]; then
			log_warning "Cannot backup $db"
			log_warning "I will continue anyway"
			log_warning "But you should check what went wrong"
		fi
	done < $MYSQL_DB

	log_verbose "Creating tar archive from *.sql in /tmp"
	tar cpzf /tmp/mysql_databases.tar.gz /tmp/*.sql &>/dev/null
	if [ $? -ne 0 ]; then
		log_error "tar exit value was $?"
		log_error "Cannot compress the databases"
		log_error "Not sure what went wrong"
		exit 1
	fi
	
	log_verbose "Deleting uncompressed databases in /tmp"
	rm /tmp/*.sql &>/dev/null

	log_verbose "Sending databases to $HOST"
	if [ $LOCAL_BACKUP == 1 ]; then
		cp /tmp/mysql_databases.tar.gz $DIR_FULL/mysql_databases.tar.gz
	else	
		scp /tmp/mysql_databases.tar.gz ${USER}@$HOST:$DIR_FULL/mysql_databases.tar.gz &> /dev/null
	fi	
	if [ $? -ne 0 ]; then
		log_error "Cannot login or connect to $HOST"
		exit 1
	fi

	log_verbose "Deleting mysql_databases.tar.gz in /tmp"
	if [ -f /tmp/mysql_databases.tar.gz ]; then
		rm /tmp/mysql_databases.tar.gz
	else
		log_warning "/tmp/mysql_databases.tar.gz does not exist"
		log_warning "Maybe the backup wasn't created?"
	fi
}

function CHECK_SSH {
	nc -z -w5 $HOST 22 &> /dev/null
	
	if [ $? -ne 0 ]; then
		log_error "Cannot connect to host $HOST via port 22"
		exit 1
	fi
	
	if ! [ -d ~/.ssh ]; then
		log_warning "Can't find ~/.ssh directory. No public key authentication possible."
		log_warning "You need to setup public key authentication with the server that will store your backups."
		log_warning "For testing purpose you can also manually type a password."
	fi
	
	if ! [ -f ~/.ssh/id_rsa ]; then
		log_warning "Can't find the privat key in your ~/.ssh directory. No public key authentication possible."
		log_warning "You need to setup public key authentication with the server that will store your backups."
		log_warning "For testing purpose you can also manually type a password."
	elif [ -f ~/.ssh/id_rsa ]; then
		log_verbose "Checking if key permissions are set to 600"
		TEST=$(stat --format=%a ~/.ssh/id_rsa)
		if [ $TEST != 600 ]; then
			log_warning "Your key permission is $TEST"
			log_warning "Please set ~/.ssh/id_rsa permissions to 600"
			log_warning "I will continue anyway, but ssh won't connect without password!"
		fi
	fi
}

function BACKUP_MBR {
# Backup partition table
	# Wrapper to silence output
	function backup_part_table {
		sfdisk --quiet -d $DISK > /tmp/part_table
	}

	log_verbose "Backing up partiton table to /tmp/part_table"

	if [ -d /tmp ]; then
		if [ -f /tmp/.test ]; then
			rm /tmp/.test &> /dev/null
		fi
		touch /tmp/.test &> /dev/null
		if [ $? -ne 0 ]; then
			log_error "/tmp not writeable"
			exit 1
		fi
	else
		log_error "/tmp doesn't exist"
		exit 1
	fi

	backup_part_table &> /dev/null

	log_verbose "Sending partition table backup to $HOST:$DIR_FULL"

	if [ -f /tmp/part_table ]; then
		if [ $LOCAL_BACKUP == 1 ]; then
			cp /tmp/part_table $DIR_FULL/part_table &> /dev/null
		else	
			scp /tmp/part_table $USER@$HOST:$DIR_FULL/part_table &> /dev/null
		fi	
		
		if [ $? -ne 0 ]; then
			log_error "Cannot login or connect to $HOST"
			exit 1
		fi
	else
		log_error "Can't copy /tmp/part_table to $HOST. File doesn't exist"
		exit 1
	fi

	log_verbose "Deleting partition table in /tmp/part_table"

	if [ -f /tmp/part_table ]; then
		rm /tmp/part_table
	fi	
}

function BACKUP_VG_LAYOUT {
	COUNTER2=0
	while [ $COUNTER2 -lt ${#VG_NAME[@]} ]; do
		# Backup lvm structure
		log_verbose "Backing up lvm structure to /tmp/lvm_structure"

		vgcfgbackup -f /tmp/lvm_structure /dev/${VG_NAME[$COUNTER2]} &> /dev/null

		if [ $? -ne 0 ]; then
			log_error "Couldn't backup the lvm structure of volume group $VG_NAME"
			exit 1
		fi

		log_verbose "Sending lvm structure to $HOST:$DIR_FULL"

		if [ -f /tmp/lvm_structure ]; then
			if [ $LOCAL_BACKUP == 1 ]; then
				cp /tmp/lvm_structure $DIR_FULL/${VG_NAME[$COUNTER2]}/lvm_structure &> /dev/null
			else
				scp /tmp/lvm_structure ${USER}@$HOST:$DIR_FULL/${VG_NAME[$COUNTER2]}/lvm_structure &> /dev/null
			fi
			if [ $? -ne 0 ]; then
				log_error "Cannot login or connect to $HOST"
				exit 1
			fi
		else
			log_error "Can't copy /tmp/lvm_structure to $HOST. File doens't exist"
			exit 1
		fi

		log_verbose "Deleting lvm structure in /tmp/lvm_structure"
		if [ -f /tmp/lvm_structure ]; then
			rm /tmp/lvm_structure
		fi	
		
		let COUNTER2=COUNTER2+1
	done	
}

function DELETE_OLD_DATA {
	log_verbose "Deleting backups older than $DAYS_OLD days in $DIR/$hostname on host $HOST"
	if [ $LOCAL_BACKUP == 1 ]; then
		find $DIR/$hostname -mindepth 1 -maxdepth 1 -type d -mtime +$DAYS_OLD -exec rm -rf {} \;
	else
		ssh ${USER}@$HOST "find $DIR/$hostname -mindepth 1 -maxdepth 1 -type d -mtime +$DAYS_OLD -exec rm -rf {} \;"
	fi	
	if [ $? -ne 0 ]; then
		log_error "Cannot login or connect to $HOST"
		exit 1
	fi
}

function IGNORE_DIR {
	if ! [ $IGNORE_DIR == 1 ]; then
		log_verbose "IGNORE_DIR is set to $IGNORE_DIR"
		log_error "$DIR_FULL on host $HOST already exists"
		log_error "Maybe todays backup was already created?"
		log_error "Set IGNORE_DIR to 1 in the config file if you want to continue anyway!"
		exit 1
	else
		log_warning "IGNORE_DIR is set to $IGNORE_DIR"
		log_warning "I will continue anyway!"
	fi
}

# Exit trap to delete the snapshots and the lockfile
function FINISH {
	log_verbose "Cleaning up..."
	COUNTER2=0
	while [ $COUNTER2 -lt ${#VG_NAME[@]} ]; do	
		LVS=/tmp/lvs_${VG_NAME[$COUNTER2]}
		if [ -f ${LVS}_${VG_NAME[$COUNTER2]} ]; then
			while read lv; do
				if [ -e /dev/${VG_NAME[$COUNTER2]}/${lv}$SNAPSHOT_SUFFIX ]; then
					lvremove -f /dev/${VG_NAME[$COUNTER2]}/${lv}$SNAPSHOT_SUFFIX &> /dev/null
					if [ $? -ne 0 ]; then
						log_error "Couldn't remove ${lv}$SNAPSHOT_SUFFIX"
					fi
				fi
			done < $LVS
		fi
		
		if [ -f $LVS ]; then
			rm $LVS
		fi
		let COUNTER2=COUNTER2+1
		
	done
	
	if [ -f $LOCKFILE ]; then
		rm $LOCKFILE
	fi
	
	if [ -f /tmp/samba4.tar.gz ]; then
		rm /tmp/samba4.tar.gz &> /dev/null
	fi
		
	if [ -d /tmp/samba ]; then
		rm -r /tmp/samba &> /dev/null
	fi
	log_verbose "Done"	
}
trap FINISH EXIT

# Checking server connection
if ! [ $LOCAL_BACKUP == 1 ];  then
	log_verbose "Checking if I can connect to $HOST"
	CHECK_SSH
fi
	
# Check if local or remote dir already exists
log_verbose "Checking if $DIR_FULL already exists on $HOST"
if [ $LOCAL_BACKUP == 1 ]; then
	if [ -d $DIR_FULL ]; then
		log_warning "Remote dir $DIR_FULL exists on $HOST"
		log_verbose "Checking IGNORE_DIR"
		IGNORE_DIR
	fi
else
	if (ssh ${USER}@$HOST "[ -d $DIR_FULL ]"); then
		log_warning "Remote dir $DIR_FULL exists on $HOST"
		log_verbose "Checking IGNORE_DIR"
		IGNORE_DIR
	fi
fi	



# Create remote backup dir
log_verbose "Creating remote dir $DIR_FULL to store the backups on $HOST"
if [ $LOCAL_BACKUP == 1 ];  then
	mkdir -p $DIR_FULL &>/dev/null
else
	ssh ${USER}@$HOST mkdir -p $DIR_FULL &>/dev/null
fi	
if [ $? -ne 0 ]; then
	log_error "Couldn't create the remote dir $DIR_FULL to store the backups"
	exit 1
fi

if [ $BACKUP_BOOT == 1 ]; then
	log_message "Starting BACKUP_BOOT"
	BACKUP_BOOT
	BACKUP_MBR
	log_message "BACKUP_BOOT is done"
fi

if [ $BACKUP_VG == 1 ]; then
	log_message "Starting BACKUP_VG"
			BACKUP_VG
			BACKUP_VG_LAYOUT
	log_message "BACKUP_VG is done"
fi

if [ $BACKUP_SAMBA == 1 ]; then
	log_message "Starting BACKUP_SAMBA"
	BACKUP_SAMBA
	log_message "BACKUP_SAMBA is done"
fi

if [ $BACKUP_MYSQL == 1 ]; then
	log_message "Starting BACKUP_MYSQL"
	BACKUP_MYSQL
	log_message "BACKUP_MYSQL is done"
fi

if [ $DELETE_OLD_DATA == 1 ]; then
	log_message "Deleting data older than $DAYS_OLD days"
	DELETE_OLD_DATA
	log_message "DELETE_OLD_DATA is done"
fi

# Remove lock file
log_verbose "Removing the lock file, if exists"
if [ -f $LOCKFILE ]; then
	rm $LOCKFILE
fi

# Calculate runtime
end=`date +%s`
log_verbose "Execution took $((end-start)) seconds"

# Write nagios log
if [ $NAGIOS == 1 ]; then
	log_verbose "Creating log file for nagios plugin"

	if [ -f $NAGIOS_LOG ]; then
		rm $NAGIOS_LOG
	fi
	echo "$hostname" >> $NAGIOS_LOG
	echo "$datum" >> $NAGIOS_LOG
	echo "$time" >> $NAGIOS_LOG
	echo "$((end-start)) seconds" >> $NAGIOS_LOG
	echo "successful" >> $NAGIOS_LOG
fi

log_success "Backup successful!"
