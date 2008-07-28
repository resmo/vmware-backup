#!/bin/sh
################################################################################
# VMWARE SERVER BACKUP SCRIPT (VSBS)
#
# Version: 0.7.0
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
# Please report any problems, improvements or corrections to me. thanks.
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
# Log should be sent to
MAIL_TO="me@example.com, you@example.com";

# Path to log file
LOG="/var/log/vmware-backup.log"
LOG_TMP="/tmp/vmware-backup.log"

# Path to the parent dir of virutal machines
VM_PARENT_PATH="/var/lib/vmware/vms"

# Where should the backups tar file go.
BACKUP_PATH="/vmware/backup"

# Wait 10 x n seconds for vmware quest shutdown, until we send a failure
# Usually no need to change this
TIMEOUT=10;
################################################################################

usage()
{
cat << EOF
usage: $0 options

This small script is used to backup a virtual machine of VMware Server.
To stop a virtual machine, SSH access to the machine (public key distribution) 
or installed VMware Tools are needed. It uses tar to backup contents,
resumes the image, then optionally compresses the content. This script is usually
started by cron (see example below).

OPTIONS:
   -h      	   	Show this message

   -H 		    	Optional, recommended: FQDN or IP of virtual host p.e. vm-host1.example.com.
			Make sure this script is able to login by Secure Shell with user root without 
			password (See http://www.debian-administration.org/articles/152). 
			
   -D		     	Directory of virtual host
   
   -F 			Backup to file name without ending, 
			.tar, .tar.gz will be automatically added.

   -C 			Optional compression (gzip or bzip)
   
   -v      		Verbose

EXAMPLE:
   00 22 * * 1-5 $0 -D webserver -F webserver-backup -H www.example.com -C gzip

DEFAULTS:
   Mails go to:		$MAIL_TO
   Log Path is:	 	$LOG
   VMware Parent Path: 	$VM_PARENT_PATH
   Backup Path: 	$BACKUP_PATH

   You can change these defaults by editing the CONFIG section in $0.

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
        echo "$1:`cat $LOG_TMP`" |  mail -s "`hostname`: VMware Backup $HOST: $1" $MAIL_TO ;
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
			vmware-cmd $VM_VMX_PATH start;
			writeLog "Tried to restart at `date` ..."
		fi

        # send a mail
        mailLog "Backup failed: $1"
        exit 1;
	fi
}

VM_PATH=
BACKUP_FILE=
HOST=
VM_NAME=
VM_VMX_FILE=

# optional
COMPRESSION=
VERBOSE=0

while getopts ÒhH:D:F:C:vÓ OPTION
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
         D)
             VM_PATH=$VM_PARENT_PATH/$OPTARG
	     VM_NAME=$OPTARG
             ;;
	 F)
             BACKUP_FILE=$OPTARG
	     ;;
	 C)
             COMPRESSION=$OPTARG
	     ;;
         v)
             VERBOSE=1
             ;;
         ?)
             usage
             exit
             ;;
     esac
done

if [[ -z $VM_PATH ]] || [[ -z $BACKUP_FILE ]] || [[ -z $HOST ]]
then
     usage
     exit 1
fi

# clear Temp Log
echo "" > $LOG_TMP

VM_VMX_PATH=`find ${VM_PATH} -type f -name *.vmx -print`
checkResult "Could not find vmx file";

TAR_NAME="${BACKUP_PATH}/${BACKUP_FILE}.tar"

# write some output to the logs
writeLog "Virtual Machine Directory $VM_PATH";
writeLog "Virtual Machine VMX File $VM_VMX_PATH";
writeLog "Virtual Machines IP or Host is $HOST";
writeLog "Output Tar Name $TAR_NAME";

if [ "${COMPRESSION}" == "" ]
then
	writeLog "Compression none";
else
	writeLog "Compression $COMPRESSION";
fi

writeLog "Starting backup at `date`";

STATE=`vmware-cmd $VM_VMX_PATH getstate | grep on | wc -l`

# grep for state = on, if its there then stop
if [ $STATE -eq 1 ]
then
  writeLog "Shutting down VMware image $VM_VMX_PATH";
  STATE=`vmware-cmd $VM_VMX_PATH getheartbeat | grep "getheartbeat() = 0"  | wc -l`
  if [ $STATE -ne 1 ]
  then
    writeLog "VMware Tools available, so shutting down with tools..."
    vmware-cmd $VM_VMX_PATH stop
  else  
    writeLog "VMWare Tools unvailable, so shutting down by ssh..."
    ssh root@"$HOST" shutdown -h now;
    checkResult "Unable to ssh to $HOST";
  fi
fi

# we try to shutdown the host, so we have to wait until it is halted
COUNTER=0;
while true;
do
  STATE=`vmware-cmd $VM_VMX_PATH getstate | grep off | wc -l`
  if [ $STATE -eq 1 ]
  then
    writeLog "Virtual Maschine has shut down.";
    break;
  fi

  # timemout?
  if [ $COUNTER -eq $TIMEOUT ]
  then
    writeLog "Virtual Maschine shut down failed.";
    writeLog "Could not shut down Virtual Machine $VM_VMX_PATH"
        mailLog "VMware Backup failed on $HOST";
    exit;
    break;
  fi

  writeLog "Virtual Maschine is still running, waiting...";
  sleep 10;
  COUNTER=$[$COUNTER+1];
done

sleep 10;

writeLog "Changing directory to $VM_PARENT_PATH"
writeLog "Taring VMWare directory $VM_PATH";
(
cd $VM_PARENT_PATH
tar cvf "${TAR_NAME}" "${VM_NAME}";
)

checkResult "Unable to create the file $TAR_NAME";
writeLog "Tar completed"

# check if the state is off, so restart the guest
STATE=`vmware-cmd $VM_VMX_PATH getstate | grep off | wc -l`

if [ $STATE -eq 1 ]
then
  writeLog "Starting VMware image $VM_VMX_PATH";
  vmware-cmd "$VM_VMX_PATH" start;
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
        # default case, print out tar name
        *)
                writeLog "Output file is $TAR_NAME";
        ;;
esac

STATE=`vmware-cmd $VM_VMX_PATH getstate | grep on | wc -l`
writeLog "Finished backup at `date`";

if [ $STATE -eq 1 ]
then
  mailLog "Backup successful"
else
  mailLog "Backup failed"
fi
exit 0