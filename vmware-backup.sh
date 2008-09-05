#!/bin/bash
################################################################################
# VMWARE SERVER BACKUP SCRIPT (VSBS)
#
# Version: 0.8.4
# Author: rene moser <mail@renemoser.net>
# URL: http://www.renemoser.net/projects
#
# Description:
# -------------------
# This small script is used to backup a virtual machine of VMware Server on 
# Linux.
# To stop a virtual machine, SSH access to the machine (public key distribution) 
# or installed VMware Tools are needed. It uses tar to backup contents,
# resumes the image, then optionally compresses the content
#
# Usage:
# -------------------
# see ./vmware-backup.sh -h
#
# Support
# -------------------
# Please report any problems, improvements or corrections to me. Thanks.
#
# License:
# -------------------
# VSBS is free software; you can redistribute it and/or modify it under the 
# terms of the GNU General Public License as published by the Free Software 
# Foundation; either version 2 of the License, or any later version.VSBS is 
# distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; 
# without even the implied warranty of MERCHANTABILITY or FITNESS FOR A 
# PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with 
# VSBS; if not, write to the Free Software Foundation, Inc., 51 Franklin St, 
# Fifth Floor, Boston, MA 02110-1301 USA
#
################################################################################
# CONFIG
################################################################################
# Log should be sent to, multiple separated by ","
MAIL_TO="root"

# Path to log file
LOG="/var/log/vmware-backup.log"
LOG_TMP="/tmp/vmware-backup.log"

# Path to the parent dir of virutal machines
VM_PARENT_PATH="/var/lib/vmware/vms"

# Where should the backups tar file go.
BACKUP_PATH="/vmware/backup"

# Wait 10 x n seconds for vmware quest shutdown, until we send a failure
# Usually no need to change this
TIMEOUT=10
################################################################################
VERSION='0.8.4'
AUTHOR='rene moser <mail@renemoser.net>'

usage()
{
cat << EOF
usage: $0 options

Version $VERSION
Author $AUTHOR

This small script is used to backup a virtual machine of VMware Server.
To stop a virtual machine, SSH access to the machine (public key distribution) 
or installed VMware Tools are needed. It uses tar to backup contents,
resumes the image, then optionally compresses the content. This script is usually
started by cron (see example below).

OPTIONS:
	-h		Show this message

	-H		FQDN or IP of virtual host p.e. vm-host1.example.com.
			Make sure this script is able to login by Secure Shell with user root without 
			password (See http://www.debian-administration.org/articles/152). 
			
  	-N		Directory of virtual host
  
	-F		Backup to File name without ending, 
			.tar, .tar.gz will be automatically added.

	-R		Use Rsync instead of tar, -F and -C will be ignored

	-D		Optional: set Destination for Rsync mode -R (SSH is used) 
			p.e. root@backup.example.com:/backup, otherwise Rsync goes to local
			backup directory specified in the config section. 
   
	-S		Optional: set restart after backup, default is 1 alias yes

	-C		Optional: compression (tar-gzip, tar-lzop, gzip or bzip), ignored if -R is set.
			
			if tar-gzip is set, the contents will be tar gzipped in one step. This may 
			take more time until the vm will be restarted, but uses less of space then taring 
			the contents, restarting the vm and gzipping afterwards (-C gzip). 
	
	-v		Verbose

EXAMPLE:
	00 22 * * 1-5 $0 -N webserver -F webserver-backup -H www.example.com -C gzip
	00 23 * * 1-5 $0 -N webserver -R -H www.example.com -v
	00 24 * * 1-5 $0 -N webserver -D root@backup.example.com:/backups -H www.example.com -v

DEFAULTS:
	Mails go to:			$MAIL_TO
	Log Path is:	 		$LOG
	VMware Parent Path:		$VM_PARENT_PATH
	Backup Path: 			$BACKUP_PATH

	You can change these settings by editing the CONFIG section in $0.

EOF
}

# write to log 
writeLog() 
{
	echo "`date`: $1" >> $LOG
	echo "`date`: $1" >> $LOG_TMP
	if [ $VERBOSE -eq 1 ] 
	then
	   	echo "`date`: $1"
	fi
}

# mail the temp log
mailLog()
{
	echo "$1:`cat $LOG_TMP`" |  mail -s "`hostname`: VMware Backup $HOST: $1" $MAIL_TO 
}

# check failures
checkResult() {

	if [ $? -ne 0 ]
	then
		# check if the vm host ist down and if so, try to restart
		STATE=`vmware-cmd $VM_VMX_PATH getstate | grep off | wc -l`

		if [ $STATE -eq 1 ]
		then
			writeLog "Starting VMware image: $VM_VMX_PATH"
			if [ $VM_START -eq 1 ]
			then
				vmware-cmd $VM_VMX_PATH start
				writeLog "Tried to restart at `date` ..."
			fi
		fi

        # send a mail
        mailLog "Backup failed: $1"
        exit 1
	fi
}

# default 
VM_PATH=
BACKUP_FILE=
HOST=
VM_NAME=
VM_VMX_FILE=
VM_START=1 
USE_RSYNC=
RSYNC_DESTINATION=
COMPRESSION=
VERBOSE=0

while getopts hH:D:N:F:S:RC:v OPTION
do
     if [ `echo "$OPTARG" | egrep '^-' | wc -l` -eq 1 ]
     then
        echo "options value are not allowed to begin with -"
        exit 1
     fi

	case $OPTION in
		h)
			usage
			exit 1
			;;
		H)
			HOST=$OPTARG
			;;
		N)
			VM_PATH=$VM_PARENT_PATH/$OPTARG
			VM_NAME=$OPTARG
			;;
		F)
			BACKUP_FILE=$OPTARG
			;;
		C)
			COMPRESSION=$OPTARG
			;;
		R)
			USE_RSYNC=1
			COMPRESSION=
			BACKUP_FILE=
			;;
		S)
			VM_START=$OPTARG
			;;
		D)
                        USE_RSYNC=1
                        COMPRESSION=
                        BACKUP_FILE=
			RSYNC_DESTINATION=$OPTARG
                        ;;		
		v)
			VERBOSE=1
			;;
		?)
			usage
			exit 1
			;;
     esac
done

# missing argument?
if [[ -z $VM_PATH ]] || [[ -z $HOST ]] || ( [[ -z $BACKUP_FILE ]] && [[ -z $USE_RSYNC ]] )
then
	usage
	exit 1
fi

# clear Temp Log
echo "" > $LOG_TMP

# looking for the vmx file
VM_VMX_PATH=`find ${VM_PATH} -type f -name *.vmx -print`
checkResult "Could not find vmx file"

# write some output to the logs
writeLog "Virtual Machine Directory ${VM_PATH}"
writeLog "Virtual Machine VMX File ${VM_VMX_PATH}"
writeLog "Virtual Machine's IP or Host is ${HOST}"
writeLog "Virtual Machine starts after backup is set to ${VM_START}"

# not using rsync
if [[ -z $USE_RSYNC ]]
	then
	TAR_NAME="${BACKUP_PATH}/${BACKUP_FILE}.tar"
	writeLog "Output Tar Name ${TAR_NAME}"
else
	writeLog "Output Rsync to Directory ${BACKUP_PATH}/${VM_NAME}"
fi

# is compression set? reseted on rsync mode don't worry
if [ "${COMPRESSION}" = "" ]
then
	writeLog "Compression none"
else
	writeLog "Compression ${COMPRESSION}"
fi

# backuping starts
writeLog "Starting backup at `date`"

# stopping virtual machine
STATE=`vmware-cmd ${VM_VMX_PATH} getstate | grep on | wc -l`
if [ $STATE -eq 1 ]
then
	writeLog "Shutting down VMware image ${VM_VMX_PATH}"
	STATE=`vmware-cmd $VM_VMX_PATH getheartbeat | grep "getheartbeat() = 0"  | wc -l`
	
	# shutting down with tools 	
	if [ $STATE -ne 1 ]
	then
		writeLog "VMware Tools available, so shutting down with tools..."
		vmware-cmd $VM_VMX_PATH stop
	
	# otherwise trying to shut down by SSH	
	else  
		writeLog "VMWare Tools unvailable, so shutting down by ssh..."
		ssh root@"$HOST" shutdown -h now
		checkResult "Unable to ssh to ${HOST}"
	fi
fi

# we tried to shutdown the host, so we have to wait until it is halted
COUNTER=0;
while true;
do
	STATE=`vmware-cmd $VM_VMX_PATH getstate | grep off | wc -l`
	if [ $STATE -eq 1 ]
	then
		writeLog "Virtual Machine has shut down."
		break
	fi

	# timemout?
	if [ $COUNTER -eq $TIMEOUT ]
	then
		writeLog "Virtual Machine shut down failed."
		writeLog "Could not shut down Virtual Machine ${VM_VMX_PATH}"
		mailLog "Backup failed"
    	exit 1
    	break
	fi

	writeLog "Virtual Machine is still running, waiting..."
	sleep 10
	COUNTER=$[$COUNTER+1]
done
sleep 10

# virtual machine has shut down
# rsyncing or taring now?
writeLog "Changing directory to ${VM_PARENT_PATH}"
if [[ -z $USE_RSYNC ]]
then
	# so taring
	writeLog "Taring VMWare directory ${VM_PATH}"
	(
	cd $VM_PARENT_PATH
	
	case $COMPRESSION in
        tar-gzip)
        	writeLog "Taring and gzipping at once"
        	TAR_NAME="${TAR_NAME}".gz
        	tar cvzf "${TAR_NAME}" "${VM_NAME}"
	;;
        tar-lzop)
		writeLog "Taring und lzoping at once"
		TAR_NAME="${TAR_NAME}".lzo
		tar --use-compress-program=lzop -cf "${TAR_NAME}" "${VM_NAME}"		
        ;;
        *)
		tar cvf "${TAR_NAME}" "${VM_NAME}"
        ;;
	esac
	)
	checkResult "Unable to create the file ${TAR_NAME}"
	writeLog "Tar to file ${TAR_NAME} completed"
else
	# so rsyncing
	writeLog "Rsyncing VMWare directory ${VM_PATH}"
	if [[ -z $RSYNC_DESTINATION ]]
	then
		(
		mkdir -p ${BACKUP_PATH}/${VM_NAME}
		cd $VM_PARENT_PATH 
		rsync -av ${VM_PATH} ${BACKUP_PATH}/${VM_NAME}
		)
	else
		writeLog "Rsyncing to Destination ${RSYNC_DESTINATION}"
		(
		cd $VM_PARENT_PATH
                rsync -avz ${VM_PATH} ${RSYNC_DESTINATION}
		)
	fi

	checkResult "Unable to rsync ${VM_PATH}"
	writeLog "Rsync completed"
fi

# check if the state is off, so restart the guest
STATE=`vmware-cmd $VM_VMX_PATH getstate | grep off | wc -l`

if [ $STATE -eq 1 ] && [ $VM_START -eq 1 ]
then
	writeLog "Starting VMware image $VM_VMX_PATH"
	vmware-cmd "$VM_VMX_PATH" start
	checkResult "Unable to restart $VM_VMX_PATH"
fi

# which compression?
case $COMPRESSION in
	bzip)
		writeLog "Bzip2ing the file"
		bzip2 "$TAR_NAME"
		checkResult "Unable to bzip2 the tar"
        ;;
	# gzip the file
	gzip)
		writeLog "Gzipping file"
		gzip "$TAR_NAME" -f --rsyncable
		checkResult "Unable to Gzip the tar"
        ;;
	*)
    	;;
esac

writeLog "Finished backup at `date`"
mailLog "Backup successful"
exit 0
