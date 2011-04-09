#!/bin/sh -f
# Author: Takanori TANIGUCHI taniguti.t_at_gmail.com

#################
# Functions
#################

#################
# USAGE
usage(){
	cat 1>&2 <<- EOF
	**** YOU NEED THE ROOT PRIVILLAGE ****
	**** This script is written for   ****
	**** Mac OS X Administrators.     ****

	USAGE::
	`/usr/bin/basename $0` /fullpath/to/srcvolume /fullpath/to/distination [stream]

	Source disk must NOT be current start up disk.
	If you add 3rd arg, "stream", image will be ready for multicast restore via network. Default behavior is NOT for multicast.

EOF
}

###################
# Logging
logmsg() {
	MYNAME=`/usr/bin/basename $0`
	NTIME=`date`
	LOGMSG="$1"
	/bin/echo "[${NTIME}] $MYNAME: ${LOGMSG}"
	/usr/bin/logger "$MYNAME: ${LOGMSG}"
}

###################
# Delte Local KDC for Mac OS X 10.5 or later
# see for more info, http://support.apple.com/kb/TS1245
DeleteLKDC() {
	if [ -f "${1}/System/Library/LaunchDaemons/com.apple.configureLocalKDC.plist" ]; then
		rm -fvr "${1}/var/db/krb5kdc"
		defaults delete "${1}/System/Library/LaunchDaemons/com.apple.configureLocalKDC" Disabled
		systemkeychain -k "${1}/Library/Keychains/System.keychain" -C -f
	fi
}

###################
# Cleaning Up files
CleaningUP() {
	HD="$1"

	# Root Home
	for i in .Trash .lesshst .viminfo .sh_history Library
	do
		rm -vrf "${HD}/private/var/root/${i}"
	done
	mkdir -m 0700 "${HD}/private/var/root/Library"
	touch "${HD}/private/var/root/Library/.localized"

	# /Library/Preferences/SystemConfiguration
	SC="${HD}/Library/Preferences/SystemConfiguration"
	for i in `ls -1 "${SC}"`
	do
		case $i in
		autodiskmount.plist )	
		;;
		com.apple.Boot.plist )
		;;
		*)
		rm -rvf "${SC}/${i}"
		;;
		esac 
	done

	# SSH Keys
	for i in key dsa_key rsa_key
	do
		rm -vf "${HD}/private/etc/ssh_host_${i}"
		rm -vf "${HD}/private/etc/ssh_host_${i}.pub"
	done

	# utmpx and remotedesktop repo
	if [ -d  "${HD}/private/var/log/asl" ]; then
		rm -rvf "${HD}/private/var/log/asl"
	fi
	for i in `ls -1 "${HD}/private/var/db/RemoteManagement/"`
	do
		rm -rvf "${HD}/private/var/db/RemoteManagement/$i"
	done

	if [ -d "${HD}/private/var/folders/" ]; then
		for i in `ls -1 "${HD}/private/var/folders/"`
		do
			rm -rvf "${HD}/private/var/folders/$i"
		done
	fi

	for i in `ls -1 "${HD}/private/var/vm/"`
	do
		rm -rvf "${HD}/private/var/vm/$i"
	done

	if [ -d "${HD}/private/var/audit" ]; then
		rm -rvf "${HD}/private/var/audit"
		mkdir -m 700 "${HD}/private/var/audit"
		chown 0:0 "${HD}/private/var/audit"
	fi
}

####################
# Repair FileSystem condition
RepairFS() {
	logmsg "[INFO] Start Repair volume of ${1}."
	diskutil repairvolume "${1}"
	logmsg "[INFO] Finished Repair volume of ${1}."

}

####################
# Repair Permissions
repairPermissions() {
	# Set owner aware by force.
	vsdbutil -a "${1}"
	logmsg "[INFO] Set owner aware of ${1}."
	logmsg "[INFO] Start Repair Parmissions of ${1}."
	diskutil repairPermissions "${1}"
	logmsg "[INFO] Finished Repair Parmissions of ${1}."
}

##################
# Scan Image for Restore
ScanImange() {
	OPT="$1"
	IMG="$2"
	logmsg "[INFO] Start image scanning for ${IMG}."
	asr  imagescan ${OPT} --source "${IMG}"
	logmsg "[INFO] Finished image scanning for ${IMG}."
}

##################
# Check Stream or not
StreamOrNot() {
	if [ "x${1}" = "xstream" ]; then
		/bin/echo "--verbose --filechecksum"
	else
		/bin/echo "--verbose --filechecksum --nostream"
	fi
}

##################
# Create dmg file
create_dmg() {
	SRC="$1"
	DMGFILE="$2"
	logmsg "[INFO] Start creating image ${DMGFILE}."
	hdiutil create -scrub -nospotlight -srcfolder "${SRC}" "${DMGFILE}"
	logmsg "[INFO] Finished creating image ${DMGFILE}."
}

##################
# Chack if set up volume or not
IsConfigured() {
	if [ -f "${1}/private/var/db/.AppleSetupDone" ]; then
		#   Get $LocalHostName
		eval `defaults read "${1}/Library/Preferences/SystemConfiguration/preferences" |	\
			grep LocalHostName | 								\
			tr '{' '\n'|grep LocalHostName|tr -d '};'| 					\
			sed s/" = "/=/g`
		/bin/echo ${LocalHostName:=NoName}
	else
		/bin/echo "Preconfigure"
	fi	
}

##################
# Check if Server or not
IsServer() {
	if [ -f "${1}/System/Library/CoreServices/ServerVersion.plist" ]; then
		/bin/echo "Server"
	else
		/bin/echo "Desktop"
	fi
}

####################################################
# PROCESS
####################################################
# MYNAME=`/usr/bin/basename $0`

# Check who exec.
WHOAMI=`/usr/bin/whoami`
logmsg "[INFO] Executed by ${WHOAMI}."
if [ ${WHOAMI} != "root" ]; then usage; exit 1; fi

# Check what system is.
THISSYSTEM=`/usr/bin/uname -s`
logmsg "[INFO] Executed on ${THISSYSTEM}."
if [ ${THISSYSTEM} != "Darwin" ]; then usage; exit 1; fi

# Check of arguments.
logmsg "[INFO] Check of Number of arguments. [$#]"
if [ $# -lt 2 ]; then usage; exit 1; fi
n=1
for i in $@
do
	logmsg "[INFO] Argv[$n]: $i."
	n=`expr $n + 1`
done

# Check Source Disk
DISKNAME=`basename "$1"`
SRCDISK="/Volumes/${DISKNAME}" 
if [ -h "$SRCDISK" ]; then usage ; exit 1 ; fi
if [ ! -f "${SRCDISK}/System/Library/CoreServices/SystemVersion.plist" ]; then usage; exit 1; fi
logmsg "[OK] Source volume is ${SRCDISK}."

# Require full path of distnation
if [ ! -d "$2" ]; then
	mkdir -p "$2"
	EXITCODE=$?
	if [ $EXITCODE -ne 0 ]; then exit $EXITCODE ; fi
fi
DESTDIR=`dirname "$2/a"`
logmsg "[OK] Destination is ${DESTDIR}."

# Stream or Not
if [ $# -eq 3 ]; then
	OPTION=`StreamOrNot $3`
else
	OPTION=`StreamOrNot "NOT"`
fi
logmsg "[INFO] asr options are ${OPTION}."

# Chack if set up volume or not
PREFIX=`IsConfigured "${SRCDISK}"`
if [ ${PREFIX} = "Preconfigure" ]; then
	logmsg "[INFO] Target system is not configured yet."
	logmsg "[INFO] Cleaning root home, Network settings and SSH keys."
	CleaningUP "${SRCDISK}"
	logmsg "[INFO] Delete Local KDC.[Preconfigure system]"
	DeleteLKDC "${SRCDISK}"
else
	logmsg "[INFO] Target system is configured."
fi

# Check if Server or not
if [ `IsServer "${SRCDISK}"` = "Server" ]; then
	versioninfo="${SRCDISK}/System/Library/CoreServices/ServerVersion"
else
	versioninfo="${SRCDISK}/System/Library/CoreServices/SystemVersion"
	logmsg "[INFO] Delete Local KDC.[Desktop]"
	DeleteLKDC "${SRCDISK}"
fi

# Get ${ProductVersion} and ${ProductBuildVersion}
eval `defaults read "$versioninfo" | sed s/" "//g| tr -d '{}'`

# Date of creation
CDATE=`date "+%Y%m%d%H%M%S"`

# DMG Name of distination.
DMGFILE=${DESTDIR}/${PREFIX}_${DISKNAME}_${ProductName}_${ProductVersion}_${ProductBuildVersion}_${CDATE}.dmg
if [ -f "${DMGFILE}" ]; then 
	logmsg "[Error] $DMGFILE already exists. Try again."
	exit 3
fi
logmsg "[OK] DMG file name is ${DMGFILE}."

# Create dmg file
RepairFS "${SRCDISK}"
repairPermissions "${SRCDISK}"
create_dmg "${SRCDISK}" "${DMGFILE}"
ScanImange "${OPTION}"  "${DMGFILE}"
logmsg "[INFO] Everything done."

exit 0
