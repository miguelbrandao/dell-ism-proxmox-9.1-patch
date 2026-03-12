#!/bin/bash
###############################################################################
#
#          Dell Inc. PROPRIETARY INFORMATION
# This software is supplied under the terms of a license agreement or
# nondisclosure agreement with Dell Inc. and may not
# be copied or disclosed except in accordance with the terms of that
# agreement.
#
# Copyright (c) 2022 Dell Inc. All Rights Reserved.
#
# Module Name:
#
#   dcism-setup.sh
#
#
# Abstract/Purpose:
#
#   Interactive Custom Install Script to cutomize the iDRAC Service Module
#   RPM Package install.
#   This interactive script will enable the user to choose the optional
#   features and make them available on the local machine.
#
# Environment:
#
#   Linux
#
###############################################################################
# Operating system ("OS") types.
# These are the return values for the following function:
#     GetOSType
#
GBL_OS_TYPE_ERROR=0
GBL_OS_TYPE_UKNOWN=1
GBL_OS_TYPE_SLES15=2
GBL_OS_TYPE_RHEL9=3
GBL_OS_TYPE_UBUNTU24=4
GBL_OS_TYPE_RHEL10=5
GBL_OS_TYPE_SLES16=6

GBL_OS_TYPE_STRING=$GBL_OS_TYPE_UKNOWN
PATH_TO_RPMS_SUFFIX=""

#Error Handling
UPDATE_SUCCESS=0
UPDATE_FAILED=1
UPDATE_NOT_REQD=2
UPDATE_FAILED_NEWER_VER_AVAILABLE=3
UPDATE_PREREQ_NA=4
SERVICE_FAILED_TO_START=5
ERROR=6
UNINSTALL_FAILED=7

BASEDIR=`dirname $0`
SCRIPT_SOURCE="installer"
SYSIDFILEPATH=""
LICENSEFILEPATH=""
LICENSEFILE="$BASEDIR/prereq/license_agreement.txt"
INSTALL_CONFIG="$BASEDIR/install.ini"
FEATURE_COUNT=0
OPTION_COUNT=1
PREDEFINE_OPTION=0
IDRAC_HARD_RESET_STR="iDRAC Hard Reset"
SUPPORT_ASSIST_STR="Support Assist"
FULLPOWER_CYCLE_STR="Full Power Cycle"
ALL_FEATURES_STR="All Features"
SNMP_TRAPS_STR="dctrapfp"
METRICINJECTION_STR="dcmetricfp"
SNMP_OMSA_TRAPS_STR="dcomsatrapfp"
SNMPGET_STR="dcsnmpgetfp"
PREFIX_FOR_SATA="NONE"
declare -A ftr
declare -A dcism_feature_list
declare -A feature_values
declare -A dcism_sections
chars=( {a..z} )
declare -A short_opts
declare -A long_opts
IDRAC_OPTION="dcos2idrac"
SSO_OPTION="dcidraclauncher"
OS2IDRAC="dcos2idracfp"
READ_ONLY_OPTION="dcidraclauncherro"
ADMIN_OPTION="dcidraclauncheradmin"
SMART_STR="dccsfp"
HISTORIC_STR="dccsfphistoricsmartlog"
AHCI_MODE_STR="AhciMode"
SNMP_LO="--snmptrap"
OMSA_LO="--snmpomsatrap"
IDRAC_PORT=""

if [ -f "$INSTALL_CONFIG" ]; then
IFS=$'\r\n'

DCISM_FEATURE_NAMES=($(grep -vE "^#|triggered" "$INSTALL_CONFIG" | awk -F"|" '{print $1}'))
DCISM_FEATURE_LIST=($(grep -vE "^#|triggered" "$INSTALL_CONFIG" | awk -F"|" '{print $2}'))
DCISM_FEATURE_ARRAY=($(grep -vE "^#|triggered" "$INSTALL_CONFIG" | awk -F"|" '{print $3}'))
DCISM_FEATURE_ARRAY+=("$IDRAC_HARD_RESET_STR")
DCISM_FEATURE_ARRAY+=("$SUPPORT_ASSIST_STR")
DCISM_FEATURE_ARRAY+=("$FULLPOWER_CYCLE_STR")
DCISM_FEATURE_ARRAY+=("All Features")
DCISM_TRIGGERABLE_FEATURE_ARRAY=($(grep -v ^# "$INSTALL_CONFIG" |grep -i "triggered"|awk -F"|" '{print $2}'))
DCISM_FEATURES_ENABLED_ARRAY=($(grep -vE "^#|triggered" "$INSTALL_CONFIG" | awk -F"|" '{print $4}'))
DCISM_FEATURES_ENABLED_ARRAY+=("true")
DCISM_FEATURES_ENABLED_ARRAY+=("true")
DCISM_FEATURES_ENABLED_ARRAY+=("true")
DCISM_FEATURES_ENABLED_ARRAY+=("false")
DCISM_SECTIONS=($(grep -vE "^#|triggered" "$INSTALL_CONFIG" | awk -F"|" '{print $1}'))
SHORTOPTS_ARR=($(grep -vE "^#|triggered" "$INSTALL_CONFIG" | awk -F"|" '{print $6}'))
LONGOPTS_ARR=($(grep -vE "^#|triggered" "$INSTALL_CONFIG" | awk -F"|" '{print $7}'))
# silent install options
SHORT_OPTS=([0]="x" [1]="a" [2]="i" [3]="d")
SHORT_OPTS+=(${SHORTOPTS_ARR[@]})
LONG_OPTS=([0]="express" [1]="autostart" [2]="install" [3]="delete")
LONG_OPTS+=(${LONGOPTS_ARR[@]})

    COUNT=${#DCISM_FEATURE_NAMES[@]}
    n=0
    for ((i=0; i<$COUNT; i++))
    do
        if [[ ! ${dcism_feature_list[@]} =~ ${DCISM_FEATURE_LIST[$i]} ]]; then
                n=`expr $n + 1`
                ftr[$n,0]+="${DCISM_FEATURE_LIST[$i]}"
                dcism_sections[$n,0]+="${DCISM_SECTIONS[$i]}"
                short_opts[$n,0]+="${SHORTOPTS_ARR[$i]}"
                long_opts[$n,0]+="${LONGOPTS_ARR[$i]}"
        fi
        m=1
        for x in "${!DCISM_FEATURE_ARRAY[@]}";
        do
                if [ "${DCISM_FEATURE_ARRAY[$x]}" == "${DCISM_FEATURE_NAMES[$i]}" ]; then
                        dcism_feature_list+="${DCISM_FEATURE_LIST[$x]}"
						char_val=`expr $m - 1`
						ftr[$n,${chars[$char_val]}]+="${DCISM_FEATURE_LIST[$x]}"
						dcism_sections[$n,${chars[$char_val]}]+="${DCISM_SECTIONS[$x]}"
						short_opts[$n,${chars[$char_val]}]+="${SHORTOPTS_ARR[$x]}"
						long_opts[$n,${chars[$char_val]}]+="${LONGOPTS_ARR[$x]}"
                        m=`expr $m + 1`
                fi
        done
   done
   n=`expr $n + 1`
ftr[$n,0]+="$IDRAC_HARD_RESET_STR"
short_opts[$n,0]+="x"
long_opts[$n,0]+="express"
n=`expr $n + 1`
ftr[$n,0]+="$SUPPORT_ASSIST_STR"
short_opts[$n,0]+="a"
long_opts[$n,0]+="autostart"
n=`expr $n + 1`
ftr[$n,0]+="$FULLPOWER_CYCLE_STR"
short_opts[$n,0]+="i"
long_opts[$n,0]+="install"
n=`expr $n + 1`
ftr[$n,0]+="$ALL_FEATURES_STR"
short_opts[$n,0]+="d"
long_opts[$n,0]+="delete"

FEATURE_COUNT=0
COUNT=${#ftr[@]}
for ((j=1;j<=$COUNT;j++)) do
    for ((i=0;i<=$COUNT;i++)) do
            if [ $i -eq 0 ]; then
                if [ ! -z "${ftr[$j,$i]}" ]; then
					value=`grep -e "${ftr[$j,$i]}" "$INSTALL_CONFIG" | awk -F"|" '{print $5}'`
					feature_values[$j,$i]=$value
					retain_j=$j
					FEATURE_COUNT=`expr $FEATURE_COUNT + 1`
                fi
            else
                char_val=`expr $i - 1`
                if [ ! -z "${ftr[$j,${chars[$char_val]}]}" ]; then
					value=`grep -e "${ftr[$j,${chars[$char_val]}]}" "$INSTALL_CONFIG" | awk -F"|" '{print $5}'`
					ENABLED_PATT=`[ "$value" == "true" ] && echo "[x]" || echo "[ ]"`
					feature_values[$j,${chars[$char_val]}]=$value
					retain_j=$j
                fi
            fi
    done
done
j=$retain_j
feature_values[$j,0]=false
j=`expr $j - 1`
feature_values[$j,0]=true
j=`expr $j - 1`
feature_values[$j,0]=true
j=`expr $j - 1`
feature_values[$j,0]=true

IFS=$' '
fi

# silent install options
SHORT_OPTS=([0]="x" [1]="a" [2]="i" [3]="d")
SHORT_OPTS+=(${SHORTOPTS_ARR[@]})
LONG_OPTS=([0]="express" [1]="autostart" [2]="install" [3]="delete")
LONG_OPTS+=(${LONGOPTS_ARR[@]})
SHORT_DEL="false"
SHORT_INSTALL="false"
MOD_CM=""
OPT_FALSE=0

FIRST_SCREEN=1
CLEAR_CONTINUE="no"

UPGRADE=0
DOWNGRADE=0
MODIFY=0
FEATURES_POPULATED=0

ARCH="x86_64"
ISM_INI_FILE="/opt/dell/srvadmin/iSM/etc/ini/dcismdy64.ini"
SERVICES_SCRIPT="/etc/init.d/dcismeng"
SELECT_ALL="false"
AUTO_START="false"
EXPRESS="false"

OS2IDRAC_INI_FILE="/opt/dell/srvadmin/iSM/etc/ini/dcos2idrac.ini"
OS2IDRAC_PORT_NUM=0
PORT_ARG_STRING="port"
# OS2IDRAC feature index in DCISM_FEATURES_ENABLED_ARRAY

# OS2IDRAC feature specified in silent install
OS2IDRAC_ENABLED="false"



LCLOG_INDEX=1

SNMPTRAP_SCRIPT="/opt/dell/srvadmin/iSM/bin/Enable-iDRACSNMPTrap.sh"
IBIA_SCRIPT="/opt/dell/srvadmin/iSM/bin/Enable-iDRACAccessHostRoute"

TEMP_INI_FILE="/opt/dell/srvadmin/iSM/tmpdcism.ini"
trap 'rm -rf "$TEMP_INI_FILE" > /dev/null 2>&1'   EXIT ERR

ISMMUTLOGGER="/opt/dell/srvadmin/iSM/lib64/dcism/ismmutlogger"
MUT_LOG_FILE="/tmp/.dcismmutlogger"
DCISM_IDRAC_LAUNCHER_INI="/opt/dell/srvadmin/iSM/etc/ini/dcismlauncher.ini"
DCCS_INI_FILE="/opt/dell/srvadmin/iSM/etc/ini/dccs.ini"

IPC_DIR="/opt/dell/srvadmin/iSM/var/lib/ipc"
#to determine which generation of server it is like 13G/14G, server_gen will store the value like 3->13G,4->14G.
#server=`dmidecode -t system | grep "Product Name" | awk -F: '{ print $2 }' | awk -F' ' '{ print $2 }'`
server_gen=0


###############################################################################
# Function : SetErrorAndInterrupt
#
#   The "tee" command used to write log, continues execution after
#   the "tee" when any part of the utility exits. Additionally, global
#   variables do not seem to be updated when execution resumes. So, all
#   exit errors are mapped to the signal HUP. kill works very quickly
#   AFTER exit is called, so to allow user messages to output, sleep
#   was added.
###############################################################################
function SetErrorAndInterrupt
{
    FF_EXIT=$1
    sleep 1
    exit $FF_EXIT
    kill -HUP $$
}

###############################################################################
##
## Function:    GetOSType
##
## Decription:  Determines the operating system type.
##
## Returns:     0 = No error
##
## Return Vars: GBL_OS_TYPE=[GBL_OS_TYPE_ERROR|
##                           GBL_OS_TYPE_UKNOWN|                
##				GBL_OS_TYPE_RHEL8|
##				GBL_OS_TYPE_RHEL9|
##				GBL_OS_TYPE_SLES15|
##				GBL_OS_TYPE_UBUNTU22|		] 
##              GBL_OS_TYPE_STRING=[|RHEL8|UBUNTU22|RHEL9|RHEL10|SLES15|UNKNOWN]
##
###############################################################################

GetOSType()
{
    # Set default values for return variables.
    GBL_OS_TYPE=${GBL_OS_TYPE_UKNOWN}
    GBL_OS_TYPE_STRING="UKNOWN"

	if [ -f /etc/os-release ]; then
		# check for operating system		
		. /etc/os-release
		OS=$NAME
		VER=`echo $VERSION_ID | cut -d"." -f1`        				
		#check for Ubuntu24.
		if [ "$OS" == "Ubuntu" ] && [ "$VER" == "24" ]; then
                                GBL_OS_TYPE=${GBL_OS_TYPE_UBUNTU24}
                                GBL_OS_TYPE_STRING="UBUNTU24"
                                PATH_TO_RPMS_SUFFIX=UBUNTU24
                                PREFIX_FOR_SATA="ubuntu24"
                fi
		#check for Debian (use UBUNTU24 packages)
		if [ "$ID" == "debian" ]; then
                                GBL_OS_TYPE=${GBL_OS_TYPE_UBUNTU24}
                                GBL_OS_TYPE_STRING="UBUNTU24"
                                PATH_TO_RPMS_SUFFIX=UBUNTU24
                                PREFIX_FOR_SATA="ubuntu24"
                fi	
		#check for RHEL8 and CentOS8
        if [[ "$ID" == "rhel" && "$VER" == "8" ]] || [[ "$ID" == "centos" &&  "$VER" == "8" ]]; then
				GBL_OS_TYPE=${GBL_OS_TYPE_RHEL8}
				GBL_OS_TYPE_STRING="RHEL8"
				PATH_TO_RPMS_SUFFIX=RHEL8
				PREFIX_FOR_SATA="el8"
		fi
	if [[ "$ID" == "rhel" && "$VER" == "9" ]] || [[ "$ID" == "centos" &&  "$VER" == "9" ]]; then
                                GBL_OS_TYPE=${GBL_OS_TYPE_RHEL9}
                                GBL_OS_TYPE_STRING="RHEL9"
                                PATH_TO_RPMS_SUFFIX=RHEL9
                                PREFIX_FOR_SATA="el9"
                fi
	#check for RHEL10.			
	if [[ "$ID" == "rhel" && "$VER" == "10" ]] || [[ "$ID" == "centos" &&  "$VER" == "10" ]]; then
								GBL_OS_TYPE=${GBL_OS_TYPE_RHEL10}
                                GBL_OS_TYPE_STRING="RHEL10"
                                PATH_TO_RPMS_SUFFIX=RHEL10
                                PREFIX_FOR_SATA="el10"
                fi			
		#check for SLES15
        if [ "$OS" == "SLES" ] && [ "$VER" == "15" ]; then
				GBL_OS_TYPE=${GBL_OS_TYPE_SLES15}
				GBL_OS_TYPE_STRING="SLES15"
				PATH_TO_RPMS_SUFFIX=SLES15
				PREFIX_FOR_SATA="sles15"
		fi
		#check for SLES16
		if [ "$OS" == "SLES" ] && [ "$VER" == "16" ]; then
                GBL_OS_TYPE=${GBL_OS_TYPE_SLES16}
                GBL_OS_TYPE_STRING="SLES16"
                PATH_TO_RPMS_SUFFIX=SLES16
                PREFIX_FOR_SATA="sles16"
        fi
    fi

    return 0
}

#function to retrieve the server generation.
function GetServerGen
{
	GetOSType
	PATH_TO_RACADMPASSTHRU="`pwd | sed "s/ /\\\ /"`"
	if [ -d $PATH_TO_RACADMPASSTHRU/prereq/racadmpassthru/$GBL_OS_TYPE_STRING ]; then
		pushd $PATH_TO_RACADMPASSTHRU/prereq/racadmpassthru/$GBL_OS_TYPE_STRING/ >/dev/null
		if [ -f racadmpassthrucli-$PREFIX_FOR_SATA ]; then
			server=`./racadmpassthrucli-$PREFIX_FOR_SATA "racadm get idrac.info.ServerGen" | grep ServerGen | awk -F= '{ print $2 }'`
			server_gen=${server:0:2}
		fi
		if [ -z $server_gen ]; then
			server_gen=0
		fi
		popd >/dev/null
	fi
}

###############################################################################
# Function : Usage
#
## Display the usage messages
###############################################################################
function Usage {
GetServerGen
cat <<EOF
Usage: ${0} [OPTION]...
iDRAC Service Module Install Utility. This Utility will run in the interactive
mode if no options are given and runs silently if one or more options are given

Options:

[-h|--help]     			Displays this help
[-i|--install]  			Installs and enables the selected features.
[-x|--express]  			Installs and enables default available features.
                			Any other options passed will be ignored.
[-d|--delete]   			Uninstall the iSM component.
[-a|--autostart]			Start the installed service after the component has
                			been installed.
EOF
COUNT=${#ftr[@]}
for ((j=1;j<=$COUNT;j++)) do
    for ((i=0;i<=$COUNT;i++)) do
                if [ $i -eq 0 ]; then
                	if [ ! -z "${ftr[$j,$i]}" ]; then
						if [[ "${dcism_sections[$j,$i]}" == "$IDRAC_OPTION" ]] || [[ "${dcism_sections[$j,$i]}" == "$SSO_OPTION" ]] || [[ "${ftr[$j,$i]}" == "$ALL_FEATURES_STR" ]] || [[ "${ftr[$j,$i]}" == "$IDRAC_HARD_RESET_STR" ]] || [[ "${ftr[$j,$i]}" == "$SUPPORT_ASSIST_STR" ]] || [[ "${ftr[$j,$i]}" == "$FULLPOWER_CYCLE_STR" ]]; then
							continue
						else
		echo -e "[-${short_opts[$j,$i]}|--${long_opts[$j,$i]}]    \t\t\tEnables the ${ftr[$j,$i]}."
						fi
                	fi
                else
                        char_val=`expr $i - 1`
						if [ ! -z "${ftr[$j,${chars[$char_val]}]}" ]; then
							if [[ "${dcism_sections[$j,${chars[$char_val]}]}" == "$OS2IDRAC" ]]; then
		echo -e "[-${short_opts[$j,${chars[$char_val]}]}|--${long_opts[$j,${chars[$char_val]}]}] [--${PORT_ARG_STRING}=<1024-65535>]\tEnables the ${ftr[$j,${chars[$char_val]}]}."
							elif [[ "${dcism_sections[$j,${chars[$char_val]}]}" == "$READ_ONLY_OPTION" ]]; then
		echo -e "[-${short_opts[$j,${chars[$char_val]}]}|--${long_opts[$j,${chars[$char_val]}]}]    \tEnables the iDRAC SSO login as Readonly user."
							elif [[ "${dcism_sections[$j,${chars[$char_val]}]}" == "$ADMIN_OPTION" ]]; then
		echo -e "[-${short_opts[$j,${chars[$char_val]}]}|--${long_opts[$j,${chars[$char_val]}]}]    \t\tEnables the iDRAC SSO login as Administrator."
							elif [[ "${dcism_sections[$j,${chars[$char_val]}]}" == "$HISTORIC_STR" ]] && [[ $server_gen -ge 14 ]]; then
		echo -e "[-${short_opts[$j,${chars[$char_val]}]}|--${long_opts[$j,${chars[$char_val]}]}]    \t\t\tEnables the ${ftr[$j,${chars[$char_val]}]}."
							elif [[ "${dcism_sections[$j,${chars[$char_val]}]}" == "$HISTORIC_STR" ]] && [[ $server_gen -le 13 ]]; then
							continue
							else
		echo -e "[-${short_opts[$j,${chars[$char_val]}]}|--${long_opts[$j,${chars[$char_val]}]}]    \t\t\tEnables the ${ftr[$j,${chars[$char_val]}]}."
							fi
						fi
                fi
    done
done
if [ -n "$1" ] && [ "$1" = "Help" ]
then
        exit 0
fi
SetErrorAndInterrupt $ERROR
}

#check whether rpm/debian is installed.
function CheckPackage()
{
   CheckOSType
   if [ $? -eq 0 ]; then
		if rpm -q dcism &> /dev/null; then
	     	return 0
		fi
   else
		if [ $(dpkg-query -W -f='${Status}' dcism 2>/dev/null | grep -c "ok installed") -eq 1 ]; then
           return 0
        fi
   fi
   return 1
}

###############################################################################
# Function : ShowLicense
# Function will show license
#
###############################################################################
function ShowLicense()
{
   CheckPackage
   if [ $? -eq 1 ]
   then
       if [ -f "$LICENSEFILEPATH" ]
       then
           more "$LICENSEFILEPATH"
           echo ""
           echo -n "Do you agree to the above license terms? ('y' for yes | 'Enter' to exit): "
           read ANSWER
           answer=`echo "${ANSWER}" | sed 's#^[[:space:]]*##; s#[[:space:]]*$##'`
           if echo "${answer}" | grep -qi "^y$"
           then
               clear
           else
               exit 0
           fi
       fi
   fi
}

# check for help
    echo "${*}" | egrep "^.*--help.*$" >/dev/null 2>&1
    if [ $? == 0 ]; then
      Usage Help
    fi

    echo "${*}" | egrep "^.*-h.*$" >/dev/null 2>&1
    if [ $? == 0 ]; then
      Usage Help
    fi

# ensure sbin utilities are available in path, so that su will also work
export PATH=/usr/kerberos/sbin:/usr/local/sbin:/sbin:/usr/sbin:$PATH

# check for root privileges
if [ ${UID} != 0 ]; then
    echo "This utility requires root privileges"
    SetErrorAndInterrupt $UPDATE_PREREQ_NA
fi



###############################################
## Prompt
###############################################

function Prompt {
  MSG="${1}"

  # prompt and get response
  echo -n "${MSG}" 1>&2
  read RESP

  # remove leading/trailing spaces
  echo "${RESP}" | sed 's#^[[:space:]]*##; s#[[:space:]]*$##'
}


#check OS type whether ubuntu or not
function CheckOSType()
{
	if [ "$OS" == "Ubuntu" ] || [ "$ID" == "debian" ]; then
		return 1
	else
		return 0
	fi
}

######################## INI FUNCTIONS SECTION START #################
function ChangeINIKeyValue
{
	INI_FILENAME=$1
	SECTION=$2
	KEY=$3
	VALUE=$4

	FOUND_SECTION=1
	FOUND_KEY=1

	#do not execute without proper parameter count
	if [ ! $# -eq 4 ]
	then
		echo "Incorrect number of parameters"
		return 1
	fi

	#exit if ini file not present
	if [ ! -f "$INI_FILENAME" ]
	then
		return 1
	fi


	#read file line by line until we hit the required section
	#and the required key. perform the job and break

	while read LINE
	do
	if [ "$FOUND_SECTION" == 0 ] && [ "$FOUND_KEY" == 0 ]
		then
		echo "$LINE" >> "$TEMP_INI_FILE"
		continue
	fi

	#check if a section is found and set flag
	echo $LINE | grep -e "^\[${SECTION}\]$"> /dev/null 2>&1
	if [ $? == 0 ]
	then
		FOUND_SECTION=0
	fi

	#check if this line is the key required
	if [ "$FOUND_SECTION" == 0 ]
	then
		echo $LINE | grep -e "${KEY}" > /dev/null 2>&1
		if [ $? == 0 ]
		then
			LINE=`echo "${LINE}" | sed "s/${KEY}=.*/${KEY}=${VALUE}/g"`
			FOUND_KEY=0
		fi
	fi
	echo "$LINE" >> "$TEMP_INI_FILE"

	done < "$INI_FILENAME"

	cp -f "$TEMP_INI_FILE" "$INI_FILENAME"
	rm -f "$TEMP_INI_FILE"

	return 0
}
	
function GetFeaturesEnabledFromINI
{
	COUNT=${#ftr[@]}
	for ((j=1;j<=$COUNT;j++)) do
    		for ((i=0;i<=$COUNT;i++)) do
                	if [ $i -eq 0 ] && [ ! -z "${ftr[$j,$i]}" ]; then
					feature_values[$j,$i]=`GetINIKeyValue "${ISM_INI_FILE}" "${dcism_sections[$j,$i]}" "feature.enabled"`
	                		echo "${feature_values[$j,$i]}" | grep -i "true" > /dev/null 2>&1
	                		if [ $? -eq 0 ]; then
        	                		feature_values[$j,$i]="true"
                			else
                        			feature_values[$j,$i]="false"
                			fi
                	else
                        	char_val=`expr $i - 1`
                		if [ ! -z "${ftr[$j,${chars[$char_val]}]}" ]; then
							feature_values[$j,${chars[$char_val]}]=`GetINIKeyValue "${ISM_INI_FILE}" "${dcism_sections[$j,${chars[$char_val]}]}" "feature.enabled"`
	                		echo "${feature_values[$j,${chars[$char_val]}]}" | grep -i "true" > /dev/null 2>&1
	                		if [ $? -eq 0 ]; then
        	                		feature_values[$j,${chars[$char_val]}]="true"
                			else
                        			feature_values[$j,${chars[$char_val]}]="false"
                			fi
                		fi
                	fi
    		done
	done
	FEATURES_POPULATED=1
}

function GetINIKeyValue
{
        INI_FILENAME=$1
        SECTION=$2
        KEY=$3
        VALUE=""

        FOUND_SECTION=1
        FOUND_KEY=1

        #do not execute without proper parameter count
        if [ ! $# -eq 3 ]
        then
			echo "Incorrect number of parameters"
			SetErrorAndInterrupt $ERROR
        fi

        #exit if ini file not present
        if [ ! -f $INI_FILENAME ]
        then
			SetErrorAndInterrupt $ERROR
        fi

        #read file line by line until we hit the required section
        #and the required key. perform the job and break

        while read LINE
        do
        if [ "$FOUND_SECTION" == 0 ] && [ "$FOUND_KEY" == 0 ]
		then
			break
        fi

        #check if a section is found and set flag
        echo $LINE | grep -e "^\[${SECTION}\]$"> /dev/null 2>&1
        if [ $? == 0 ]
		then
			FOUND_SECTION=0
		fi

        #check if this line is the key required
        if [ "$FOUND_SECTION" == 0 ]
        then
			echo $LINE | grep -e "${KEY}" > /dev/null 2>&1
			if [ $? == 0 ]
			then
				VALUE=`echo "${LINE}" | awk -F= '{print$2}'`
				FOUND_KEY=0			
				echo $VALUE
				return 0
			fi
        fi
        done < $INI_FILENAME
        #return ""
}

#check package version during upgrade, modify
function PackageVersionVerify()
{
	PKG_VER=$1
	PKG_VER_TO_INSTALL=$2
	if [ ! -z $PKG_VER_TO_INSTALL ]; then
		if [ "$PKG_VER_TO_INSTALL" == "$PKG_VER" ]; then
			FIRST_SCREEN=2
			MODIFY=1
		elif [ "$PKG_VER_TO_INSTALL" \> "$PKG_VER" ]; then
			# upgrade
			FIRST_SCREEN=1
			UPGRADE=1
		elif [ "$PKG_VER_TO_INSTALL" \< "$PKG_VER" ]; then
			#downgrade -- do not support
			DOWNGRADE=1
			#exit here for silent install
			if [ ! -z "${MOD_CM}" ]
			then
				exit $UPDATE_FAILED_NEWER_VER_AVAILABLE
			fi	
		fi
	else
		# giving random number as 0=install 1=upgrade 2=uninstall (from webpack perspective) 
		# using 3 as script is executed within sbin dir or rpm/debian file not found.
		FIRST_SCREEN=3 
		SCRIPT_SOURCE="sbin"
	fi
}
######################## INI FUNCTIONS SECTION END #################

function CheckiSMInstalled
{
	PKG_NAMES=""
	PKG_NAME=""	
	PKG_VER_TO_INSTALL=""
	CheckOSType
	if [ $? -eq 0 ]; then	
		PKG_NAMES=`rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH} %{VENDOR}\n' dcism | grep 'Dell Inc\.' 2>/dev/null` 
		PKG_NAME=`echo $PKG_NAMES | cut -d " " -f 1`
		if [ ! -z $PKG_NAME ]; then
			PKG_VER=`rpm -q $PKG_NAME --qf "%{version}"|sed "s/\.//g"`   
			PKG_VER_TO_INSTALL=`rpm -qp "$SYSIDFILEPATH/$GBL_OS_TYPE_STRING/$ARCH/dcism*.rpm" --qf "%{version}" 2>/dev/null |sed "s/\.//g"`
			PackageVersionVerify $PKG_VER $PKG_VER_TO_INSTALL
			return 0
		fi
	else	
		CheckPackage
		if [ $? -eq 0 ]; then	
			PKG_NAME=`dpkg -s dcism | grep Package  | awk '{ print $2 }'`
			PKG_VER=`dpkg -s dcism | grep Version | awk '{ print $2 }'`
			PKG_ARC=`dpkg -s dcism | grep Architecture | awk '{ print $2 }'`
			PKG_NAME=$PKG_NAME"-"$PKG_VER"."$PKG_ARC
			PKG_VER="$(cut -d'-' -f1 <<<"$PKG_VER")"
			if [ ! -z $PKG_NAME ]; then
				if [ -d $SYSIDFILEPATH/$GBL_OS_TYPE_STRING/$ARCH ]; then
					CMD="dpkg-deb -f "$SYSIDFILEPATH/$GBL_OS_TYPE_STRING/$ARCH/`ls $SYSIDFILEPATH/$GBL_OS_TYPE_STRING/$ARCH/ | grep deb`" Version"
					PKG_VER_TO_INSTALL=`$CMD`
					PKG_VER_TO_INSTALL="$(cut -d'-' -f1 <<<"$PKG_VER_TO_INSTALL")"
				fi
				PackageVersionVerify $PKG_VER $PKG_VER_TO_INSTALL
				return 0
			fi
		fi
	fi
	return 1
}

###############################################################################
#  Function : PrintGreetings
#
###############################################################################

function PrintGreetings {
  cat <<EOF

#################################################

  OpenManage || iDRAC Service Module

#################################################

EOF
}

function ShowInstallOptions
{
    if [ "$FIRST_SCREEN" == 2 ]
    then
  cat <<EOF
   The version of iDRAC Service Module that you are trying to install is already installed.
   Select from the available options below.

EOF
    fi
    if [ "$FIRST_SCREEN" == 3 ]
    then
      cat <<EOF
   The iDRAC Service Module is already installed.
   Select from the available options below.

EOF
    return 0
    fi

    if [ "$UPGRADE" == 1 ] ; then
    cat <<EOF
   A previous verion of IDRAC Service Module ($PKG_NAME) is already installed with following features enabled.
   Please add/remove features required for upgrade

EOF
    fi
    if [ "$DOWNGRADE" == 1 ]; then
      cat <<EOF
   A newer version of IDRAC Service Module ($PKG_NAME) is already installed. Quitting !.

EOF
      exit $UPDATE_FAILED_NEWER_VER_AVAILABLE
    fi
    echo ""
    echo "    Available feature options: "
    echo ""
 


COUNT=${#ftr[@]}
for ((j=1;j<=$COUNT;j++)) do
    for ((i=0;i<=$COUNT;i++)) do
                if [ $i -eq 0 ] && [ ! -z "${feature_values[$j,$i]}" ]; then
                		value=${feature_values[$j,$i]}
                		ENABLED_PATT=`[ "$value" == "true" ] && echo "[x]" || echo "[ ]"`
                        	if [ "${ftr[$j,0]}" == "$IDRAC_HARD_RESET_STR" ] || [ "${ftr[$j,0]}" == "$SUPPORT_ASSIST_STR" ] || [ "${ftr[$j,0]}" == "$FULLPOWER_CYCLE_STR" ]; then
                        echo -e "       "$j"." ${ftr[$j,$i]}
                        else
                        echo -e "   "$ENABLED_PATT $j"." ${ftr[$j,$i]}
                        	fi
                else
			char_val=`expr $i - 1`
			if [ ! -z "${ftr[$j,${chars[$char_val]}]}" ]; then
                		value=${feature_values[$j,${chars[$char_val]}]}
                		ENABLED_PATT=`[ "$value" == "true" ] && echo "[x]" || echo "[ ]"`
						if [ "${dcism_sections[$j,${chars[$char_val]}]}" == "$HISTORIC_STR" ] && [ $server_gen -ge 14 ]; then
                        echo -e "\t   "$ENABLED_PATT ${chars[$char_val]}"." ${ftr[$j,${chars[$char_val]}]}
                                elif [ "${dcism_sections[$j,${chars[$char_val]}]}" == "$HISTORIC_STR" ] && [ $server_gen -le 13 ]; then
                                        continue
                                else
                        echo -e "\t   "$ENABLED_PATT ${chars[$char_val]}"." ${ftr[$j,${chars[$char_val]}]}
				fi
			fi
                fi
    done
done


    echo ""
    echo ""
}

function ValidateUserSelection
{
    if [ $1 -gt 0 -a $1 -le $FEATURE_COUNT ]; then
       return 0
        else
           return 1
        fi
}


###############################################################################
# Function : AddLongOpt
#
## Process long command line options
###############################################################################
function AddLongOpt {

  local i=0
  local j=0
  COUNT=${#ftr[@]}
for ((j=1;j<=$COUNT;j++)) do
    for ((i=0;i<=$COUNT;i++)) do
                if [ $i -eq 0 ] && [ ! -z "${feature_values[$j,$i]}" ]; then
                                if [ "${1}" == "${long_opts[$j,$i]}" ]; then
                                        feature_values[$j,$i]=true
                                        FEATURE_OPT="true"
                                fi
                else
                        char_val=`expr $i - 1`
                        if [ ! -z "${feature_values[$j,${chars[$char_val]}]}" ]; then
                                if [ "${1}" == "${long_opts[$j,${chars[$char_val]}]}" ]; then
                                        feature_values[$j,${chars[$char_val]}]=true
                                        FEATURE_OPT="true"
                                fi
                        fi
                fi
    done
done


  if [ "${1}" == "express" ]; then
        EXPRESS="true"
  elif [ "${1}" == "install" ]; then
        SHORT_INSTALL="true"
  elif [ "${1}" == "delete" ]; then
        SHORT_DEL="true"
  elif [ "${1}" == "autostart" ]; then
    AUTO_START="true"
  elif [ "${FEATURE_OPT}" != "true" ] && [ ${1} != "help" ] ; then
	echo "Invalid Option ${1}. Please see usage"
	Usage Help
  fi
}

###############################################################################
# Function : ShortOptionFalse 
#
#This will check if supplied options are one of the feature available in install.ini file. Then it will make all feature false and later code will make only user selected
#options true. if none of the feture is provided by user then enabled feature list will be taken from install.ini file.
###############################################################################
function ShortOptionFalse {
if [ -f $INSTALL_CONFIG ]; then
   local i=0
   local j=1
   TEST=`grep -vE "^#|triggered" "$INSTALL_CONFIG" | awk -F"|" '{print $6}' | tr -d '\n'`
   #grep -vE "^#|triggered" "$INSTALL_CONFIG" | awk -F"|" '{print $6}' | tr -d '\n'| grep -E `echo ${1}| sed "s/[$TEST]/&\|/g"` >/dev/null 2>&1
   #RET=$?
   #echo "RET value:"$RET
   #if [ $RET == 0 ] && [ $OPT_FALSE == 0 ]; then
   if  [ $OPT_FALSE == 0 ]; then
   if grep -q "${1}" <<< "$TEST"; then
	COUNT=${#ftr[@]}
	for ((j=1;j<=$COUNT;j++)) do
		for ((i=0;i<=$COUNT;i++)) do
					if [ $i -eq 0 ] && [ ! -z "${feature_values[$j,$i]}" ]; then
								feature_values[$j,$i]="false"
								OPT_FALSE=1
					else
							char_val=`expr $i - 1`
							if [ ! -z "${ftr[$j,${chars[$char_val]}]}" ]; then
								feature_values[$j,${chars[$char_val]}]="false"
								OPT_FALSE=1
							fi
					fi
		done
	done
   fi
   fi
fi

}
###############################################################################
# Function : AddShortOpt
#
## Process short command line options
###############################################################################
function AddShortOpt {

   local i=0
   local j=1
   for SHORT_OPT in `echo "${1}" | sed "s/[a-zO]/& /g"`; do
   COUNT=${#ftr[@]}
	for ((j=1;j<=$COUNT;j++)) do
		for ((i=0;i<=$COUNT;i++)) do
					if [ $i -eq 0 ] && [ ! -z "${feature_values[$j,$i]}" ]; then
								if [ "${SHORT_OPT}" == "${short_opts[$j,$i]}" ]; then
									feature_values[$j,$i]="true"
									FEATURE_OPT="true"
								fi
					else
							char_val=`expr $i - 1`
							if [ ! -z "${feature_values[$j,${chars[$char_val]}]}" ]; then
								if [ "${SHORT_OPT}" == "${short_opts[$j,${chars[$char_val]}]}" ]; then
									feature_values[$j,${chars[$char_val]}]="true"
									FEATURE_OPT="true"
								fi
							fi
					fi
		done
	done

    if [ "${SHORT_OPT}" == "x" ]; then
                EXPRESS="true"
    elif [ "${SHORT_OPT}" == "d" ]; then
                SHORT_DEL="true"
    elif [ "${SHORT_OPT}" == "i" ]; then
                SHORT_INSTALL="true"
    elif [ "${SHORT_OPT}" == "a" ]; then
                AUTO_START="true"
    elif [ "${FEATURE_OPT}" != "true" ] && [ ${1} != "h" ]; then
		echo "Invalid Option ${1}. Please see usage"
		Usage Help
    fi

   
  done
}

###############################################################################
# Function : LongOptionFalse 
#
#This will check if supplied options are one of the feature available in install.ini file. Then it will make all feature false and later code will make only user selected
#options true. if none of the feture is provided by user then enabled feature list will be taken from install.ini file.
###############################################################################
function LongOptionFalse {
    local i=0
    local j=1
if [ -f $INSTALL_CONFIG ]; then
    grep -vE "^#|triggered" "$INSTALL_CONFIG" | awk -F"|" '{print $7}' | tr  '\n' ' '|grep -E `echo "${1}" | tr -d '-'|sed -e "s/ /|/g"` >/dev/null 2>&1
    RET=$?
    if [ $RET == 0 ] && [ $OPT_FALSE == 0 ]; then
		COUNT=${#ftr[@]}
		for ((j=1;j<=$COUNT;j++)) do
			for ((i=0;i<=$COUNT;i++)) do
						if [ $i -eq 0 ] && [ ! -z "${ftr[$j,$i]}" ]; then
									feature_values[$j,$i]=false
									OPT_FALSE=1
						else
								char_val=`expr $i - 1`
								if [ ! -z "${ftr[$j,${chars[$char_val]}]}" ]; then
									feature_values[$j,${chars[$char_val]}]=false
									OPT_FALSE=1
								fi
						fi
			done
		done
    fi
fi
}

###############################################################################
# Function : ValidateOpts
#
## Validate command line options
###############################################################################
function ValidateOpts {
  if [ $# -gt 0 ]; then
    # invald characters
    #BY  added //,.,_,0-9,A-Z
    echo "${*}" | sed "s/ //g" | egrep "^[-/._a-zA-Z0-9O=//]+$" >/dev/null 2>&1
    if [ $? != 0 ]; then
      echo "Invalid Options, please see the usage below"
      echo ""
      Usage
    fi

    MOD_CM=$*
	
	local OMSA_FLAG="false"
	local SNMP_FLAG="false"
	
	for param in $MOD_CM; do
		if [ "${param}" == "-So" ] || [ "${param}" == "$OMSA_LO" ]; then
		  OMSA_FLAG="true"
		fi
		if [ "${param}" == "-s" ] || [ "${param}" == "$SNMP_LO" ]; then
			SNMP_FLAG="true"
		fi
	done
	if [ "${OMSA_FLAG}" == "true" ] && [ "${SNMP_FLAG}" == "false" ] ; then
		MOD_CM+=" -s"
	fi
	
    local i=0
		LONG_READ_ONLY_ENABLED="false"
		LONG_ADMIN_ENABLED="false"
		SHORT_READ_ONLY_ENABLED="false"
		SHORT_ADMIN_ENABLED="false"
# replace  $* by $MOD_CM which does not contain --prefix <path>
for param in $MOD_CM; do
      # check for long option
      echo "${param}" | egrep "^--[a-zO2A-Z\-]+$" >/dev/null 2>&1
      if [ $? == 0 ]; then
        GOOD_LONG_OPT=1
	COUNT=${#long_opts[@]}	
	local j=0
	local i=0
	for ((j=1;j<=$COUNT;j++)) do
    	for ((i=0;i<=$COUNT;i++)) do
		if [ $i -eq 0 ] && [ ! -z "${long_opts[$j,$i]}" ]; then
          		if [ "${param}" == "--${long_opts[$j,$i]}" ]; then
            			GOOD_LONG_OPT=0
	    			LongOptionFalse "${MOD_CM}"
            			AddLongOpt ${long_opts[$j,$i]}
			fi
		else
			char_val=`expr $i - 1`
          		if [ ! -z "${long_opts[$j,${chars[$char_val]}]}" ]  && [ "${param}" == "--${long_opts[$j,${chars[$char_val]}]}" ]; then
            			GOOD_LONG_OPT=0
				if [ "${dcism_sections[$j,${chars[$char_val]}]}" == "$OS2IDRAC" ] && [ "${param}" == "--${long_opts[$j,${chars[$char_val]}]}" ]; then
					OS2IDRAC_ENABLED="true"
				fi
            			if [ "${dcism_sections[$j,${chars[$char_val]}]}" == "$READ_ONLY_OPTION" ] && [ "${param}" == "--${long_opts[$j,${chars[$char_val]}]}" ]; then
                			LONG_READ_ONLY_ENABLED="true"
            			fi
            			if [ "${dcism_sections[$j,${chars[$char_val]}]}" == "$ADMIN_OPTION" ] && [ "${param}" == "--${long_opts[$j,${chars[$char_val]}]}" ]; then
                			LONG_ADMIN_ENABLED="true"
            			fi
	    			LongOptionFalse "${MOD_CM}"
				char_val=`expr $i - 1`
            			AddLongOpt ${long_opts[$j,${chars[$char_val]}]}
			fi
          	fi
        done
	done
	if [ "$LONG_READ_ONLY_ENABLED" == "true" ] && [ "$LONG_ADMIN_ENABLED" == "true" ]; then
		echo "Invalid Option, cannot use both Read only and Admin for SSO"
		exit 1
	fi

        if [ ${GOOD_LONG_OPT} != 0 ]; then
          echo "Invalid Option ${param}, please see the usage below"
          Usage
        fi
      else
        # check for short option
        VALID_SHORT_OPTS=`echo "${SHORT_OPTS[*]}" | sed "s/ //g"`
        echo "${param}" | egrep "^-[${VALID_SHORT_OPTS}]+$" >/dev/null 2>&1
        if [ $? == 0 ]; then
          TEMP_OPT=`echo "${param}" | sed "s/-//"`
	  SHORT_COUNT=${#short_opts[@]}
          for ((k=1;k<=$SHORT_COUNT;k++)) do
          for ((m=0;m<=$SHORT_COUNT;m++)) do
                if [ $m -eq 0 ]; then
	  		ShortOptionFalse ${TEMP_OPT}
          		AddShortOpt ${TEMP_OPT}
		else
			char_val=`expr $m - 1`
          		if [ ! -z "${short_opts[$k,${chars[$char_val]}]}" ]  && [ "${TEMP_OPT}" == "${short_opts[$k,${chars[$char_val]}]}" ]; then
				if [ "${dcism_sections[$k,${chars[$char_val]}]}" == "$OS2IDRAC" ] && [ "${TEMP_OPT}" == "${short_opts[$k,${chars[$char_val]}]}" ]; then
					OS2IDRAC_ENABLED="true"
				fi
	  		if [ "${dcism_sections[$k,${chars[$char_val]}]}" == "$READ_ONLY_OPTION" ] && [ "${TEMP_OPT}" == "${short_opts[$k,${chars[$char_val]}]}" ]; then
          			SHORT_READ_ONLY_ENABLED="true"
          		fi
			if [ "${dcism_sections[$k,${chars[$char_val]}]}" == "$ADMIN_OPTION" ] && [ "${TEMP_OPT}" == "${short_opts[$k,${chars[$char_val]}]}" ]; then
          			SHORT_ADMIN_ENABLED="true"
          		fi
	  		ShortOptionFalse ${TEMP_OPT}
          		AddShortOpt ${TEMP_OPT}
		fi
		fi
	  done
  	  done
	  if [ "$SHORT_READ_ONLY_ENABLED" == "true" ] && [ "$SHORT_ADMIN_ENABLED" == "true" ]; then
		echo "Invalid Option, cannot use both Read only and Admin for SSO"
		exit 1
	  fi
        else
		echo "${param}" | egrep "^--${PORT_ARG_STRING}=[0-9]+$" >/dev/null 2>&1
		if [ $? == 0 ]; then
			OS2IDRAC_PORT_NUM=`echo "${param}" | sed "s/--${PORT_ARG_STRING}=//g"`
			if ! ( [[ $OS2IDRAC_PORT_NUM =~ ^[0-9]+$ ]] && (( $OS2IDRAC_PORT_NUM > 1023 )) && (( $OS2IDRAC_PORT_NUM < 65536 )) ); then
				echo "Invalid Port number, please see the usage below"
				Usage
			fi
		else
			echo "Invalid Option ${param}, please see the usage below"
			Usage
		fi
        fi
      fi
done
  fi
}
###############################################################################
#
#  function CheckForMultipleSelection
#
#
#
###############################################################################

function CheckForMultipleSelection {
    # remove any space characters
    STRIPPED_INPUT=`echo "$1" | sed "s/ //g"`

    OPTPKGARRLEN=$OPTION_COUNT
    ARR_IDX=1
    # only process multiple selection less or eq to arr len
    while [ ! $ARR_IDX -gt $OPTPKGARRLEN ] && [ ! -z "$STRIPPED_INPUT" ];
    do
        INDEX=`expr index "$STRIPPED_INPUT" ","`
        LEN=`expr length $STRIPPED_INPUT`
        if [ $INDEX == 0 ];
        then
            ValidateUserSelection $STRIPPED_INPUT
            if [ $? == 0 ];
            then
                #UpdatePkgSlection
                                toggle_feature_choice $STRIPPED_INPUT
            fi
            break
        elif [ $INDEX -lt $LEN ] || [ $INDEX == $LEN ];
        then
            INDEX=`expr $INDEX - 1`
            NUM_INPUT=`expr substr "$STRIPPED_INPUT" 1 $INDEX`
            if [ ! -z "$NUM_INPUT" ];
            then
                ValidateUserSelection $NUM_INPUT
                if [ $? == 0 ];
                then
                    #UpdatePkgSlection
                                        toggle_feature_choice $NUM_INPUT
                fi
                INDEX=`expr $INDEX + 2`
                STRIPPED_INPUT=`expr substr "$STRIPPED_INPUT" $INDEX $LEN`
                ARR_IDX=`expr $ARR_IDX + 1`
            else
                break
            fi
        else
           break
        fi
    done
}

#########################################################################
#Function: ValidateSubOption
#function to validate sub option like 4.a,4.b etc. is valid or not.
#
#########################################################################
function ValidateSubOption
{
option=$1
for suboption in $(echo $option | sed "s/,/ /g")
do
	if [[ $suboption == *.* ]] ; then
	resp=`echo $suboption | sed -e 's/\./,/'`
	COUNT=${#ftr[@]}
	for ((j=1;j<=$COUNT;j++)) do
		for ((i=0;i<=$COUNT;i++)) do
			if [ $i -eq 0 ]; then
				continue
			else
				char_val=`expr $i - 1`
				if [ -z "${ftr[$resp]}" ]; then
					return 1
				fi
			fi
		done
	done
	fi
done
return 0
}

function suboptionforSNMP
{
option1=$1
omsa=false
snmp=false
for suboption in $(echo $option1 | sed "s/,/ /g")
do
	if [ "$suboption" == "4.c" ]; then
		omsa=true
	fi
	if [ "$suboption" == "4.b" ] ; then
		snmp=true
	fi
done

if [ "$omsa" == "true" ] && [ "$snmp" == "true" ]; then
	return 1;
fi
return 0;
}

##########################################################################
#Function: DeselectFeatures
#function to select previously selected option if All Features option is enabled.
#
##########################################################################
function DeselectFeatures
{
if [ "${ftr[$FEATURE_COUNT,0]}" == "$ALL_FEATURES_STR" ] && [ "${feature_values[$FEATURE_COUNT,0]}" == "true" ]; then
COUNT=${#ftr[@]}
for ((j=1;j<=$COUNT;j++)) do
    for ((i=0;i<=$COUNT;i++)) do
            if [ $i -eq 0 ]; then
                if [ ! -z "${ftr[$j,$i]}" ]; then
				if [[ "${ftr[$j,$i]}" == "$IDRAC_HARD_RESET_STR" ]] || [[ "${ftr[$j,$i]}" == "$SUPPORT_ASSIST_STR" ]] || [[ "${ftr[$j,$i]}" == "$FULLPOWER_CYCLE_STR" ]]; then
                                             continue
		                 else			    
					feature_values[$j,$i]=false
				fi
                fi
            else
                char_val=`expr $i - 1`
                if [ ! -z "${ftr[$j,${chars[$char_val]}]}" ]; then
			feature_values[$j,${chars[$char_val]}]=false
                fi
            fi
    done
done
fi
}
#############################################################
#
#function:SetInput
#set the input read from user to feature_value array
#
#
#
############################################################
function SetInput
{
#DeselectFeatures
RESP=$1
omsaoption=false
if [[ $RESP == *,* ]] ; then
	mails2=$RESP
	ValidateSubOption $mails2
	
	if [ $? -eq 1 ]; then 
		return 1 
	fi

	suboptionforSNMP $mails2
	
	if [ $? -eq 1 ]; then
		omsaoption=true
	fi
	for x in $(echo $mails2 | sed "s/,/ /g")
		do
		#DeselectFeatures
        if [[ $x == *.* ]] ; then
                resp=`echo $x | sed -e 's/\./,/'`
		ret=`echo $resp | cut -d "," -f1`
        	if [ "${dcism_sections[$ret,0]}" == "$SSO_OPTION" ]; then
				k=1
				flag=false
				while [ ${feature_values[$ret,0]} ]
				do
					char_val=`expr $k - 1`
					if [ ! -z "${feature_values[$ret,${chars[$char_val]}]}" ]; then
				 		if [ "$resp" == "$ret,${chars[$char_val]}" ]; then
							if [ "${feature_values[$resp]}" == "false" ]; then
									feature_values[$resp]=true
									flag=true
							else
									feature_values[$resp]=false
							fi
				 		elif [ ! -z "${dcism_sections[$ret,${chars[$char_val]}]}" ]; then
									feature_values[$ret,${chars[$char_val]}]=false
				 		fi
					 	k=`expr $k + 1`
					else
						 break
					fi
				done
				if [ "$flag" == "false" ]; then
								feature_values[$ret,0]=false
						else
								feature_values[$ret,0]=true
				fi
        	elif [ "${dcism_sections[$resp]}" == "$HISTORIC_STR" ]; then #setting the value for Periodic log feature.
                	if [ "${feature_values[$resp]}" == "false" ]; then
                        	feature_values[$resp]=true
                        	feature_values[$ret,0]=true
                	else
                        	feature_values[$resp]=false
                	fi
			else
				if [ "${dcism_sections[$resp]}" == "$SNMP_OMSA_TRAPS_STR" ]; then
					if [ "${feature_values[$resp]}" == "false" ]; then
                        feature_values[$resp]=true
						feature_values[$ret,0]=true
						for ((i=0; i<$COUNT; i++))
						do
								char_val=`expr $i - 1`
								if [ "${dcism_sections[$ret,${chars[$char_val]}]}" == "$SNMP_TRAPS_STR"  ]; then
									feature_values[$ret,${chars[$char_val]}]=true
								fi
						done
                else
                        feature_values[$resp]=false
						if [ "${omsaoption}" == "true" ]; then
							for ((i=0; i<$COUNT; i++))
							do
								char_val=`expr $i - 1`
								if [ "${dcism_sections[$ret,${chars[$char_val]}]}" == "$SNMP_TRAPS_STR"  ]; then
									feature_values[$ret,${chars[$char_val]}]=false
								fi
							done
						fi
					fi
			elif [ "${dcism_sections[$resp]}" == "$SNMP_TRAPS_STR" ]; then
				if [ "${omsaoption}" == "false" ]; then
					if [ "${feature_values[$resp]}" == "false" ]; then
                        feature_values[$resp]=true
						feature_values[$ret,0]=true
                else
                        feature_values[$resp]=false
						for ((i=0; i<$COUNT; i++))
						do
								char_val=`expr $i - 1`
								if [ "${dcism_sections[$ret,${chars[$char_val]}]}" == "$SNMP_OMSA_TRAPS_STR"  ]; then
									feature_values[$ret,${chars[$char_val]}]=false
								fi
						done
					fi
                fi
			else
                if [ "${feature_values[$resp]}" == "false" ]; then
                    	feature_values[$resp]=true
                else
                        feature_values[$resp]=false
                fi
			fi
                k=1
				flag=false
                while [ ${feature_values[$ret,0]} ]
                do
                	char_val=`expr $k - 1`
                        if [ ! -z "${feature_values[$ret,${chars[$char_val]}]}" ]; then
                                if [ "${feature_values[$ret,${chars[$char_val]}]}" == "true" ]; then
									flag=true
								fi
                                k=`expr $k + 1`
                        else
                                 break
                        fi
                done
				if [ "$flag" == "true" ]; then
						feature_values[$ret,0]=true
				else
						feature_values[$ret,0]=false
                fi
	fi
	elif [ "${dcism_sections[$x,0]}" == "$IDRAC_OPTION" ]; then
                if [ "${feature_values[$x,0]}" == "false" ]; then
                        feature_values[$x,0]=true
                        k=1
                        while [ ${feature_values[$x,0]} ]
                        do
                                char_val=`expr $k - 1`
                                if [ ! -z ${feature_values[$x,${chars[$char_val]}]} ]; then
                                        feature_values[$x,${chars[$char_val]}]=true
                                        k=`expr $k + 1`
                                else
                                        break
                                fi
                        done
                else
                        feature_values[$x,0]=false
                        k=1
                        while [ ${feature_values[$x,0]} ]
                        do
                                char_val=`expr $k - 1`
                                if [ ! -z ${feature_values[$x,${chars[$char_val]}]} ]; then
                                        feature_values[$x,${chars[$char_val]}]=false
                                        k=`expr $k + 1`
                                else
                                        break
                                fi
                        done
                fi
	elif [ "${dcism_sections[$x,0]}" == "$SSO_OPTION" ]; then
                if [ "${feature_values[$x,0]}" == "false" ]; then
                        feature_values[$x,0]=true
                        k=1
						char_val=`expr $k - 1`
                        feature_values[$x,${chars[$char_val]}]=true
                        k=`expr $k + 1`
                        while [ "${feature_values[$x,0]}" ]
                        do
                		char_val=`expr $k - 1`
                                if [ ! -z "${feature_values[$x,${chars[$char_val]}]}" ]; then
                                        feature_values[$x,${chars[$char_val]}]=false
                                        k=`expr $k + 1`
                                else
                                        break
                                fi
                        done
                else
                        feature_values[$x,0]=false
                        k=1
                        while [ ${feature_values[$x,0]} ]
                        do
                		char_val=`expr $k - 1`
                                if [ ! -z "${feature_values[$x,${chars[$char_val]}]}" ]; then
                                        feature_values[$x,${chars[$char_val]}]=false
                                        k=`expr $k + 1`
                                else
                                        break
                                fi
                        done
                fi
	elif [ "${ftr[$x,0]}" == "$ALL_FEATURES_STR" ]; then
				COUNT=${#ftr[@]}
				for ((j=1;j<=$COUNT;j++)) do
						for ((i=0;i<=$COUNT;i++)) do
							if [ $i -eq 0 ] && [ ! -z "${ftr[$j,$i]}" ]; then
									feature_values[$j,$i]=false
							else
									char_val=`expr $i - 1`
								if [ ! -z "${ftr[$j,${chars[$char_val]}]}" ]; then
									feature_values[$j,${chars[$char_val]}]=false
								fi
							fi
						done
				done
                for ((j=1;j<=$COUNT;j++)) do
                        for ((i=0;i<=$COUNT;i++)) do
							if [ $i -eq 0 ] && [ ! -z "${feature_values[$j,$i]}" ]; then
												feature_values[$j,$i]=true
							else
								char_val=`expr $i - 1`
								if [ ! -z "${ftr[$j,${chars[$char_val]}]}" ]; then
									if [ "${dcism_sections[$j,0]}" == "$SSO_OPTION" ]; then
										 feature_values[$j,0]=true
										 if [ "${dcism_sections[$j,${chars[$char_val]}]}" == "$READ_ONLY_OPTION" ]; then
												feature_values[$j,${chars[$char_val]}]=true
										else
												feature_values[$j,${chars[$char_val]}]=false
										fi
									else
										feature_values[$j,${chars[$char_val]}]=true
									fi
								fi
							fi
                        done
                done
        elif [ "${dcism_sections[$x,0]}" == "$SMART_STR" ]; then
                if [ "${feature_values[$x,0]}" == "false" ]; then
                	feature_values[$x,0]=true
                        k=1
                        while [ ${feature_values[$x,0]} ]
                        do
                		char_val=`expr $k - 1`
                                if [ ! -z "${feature_values[$x,${chars[$char_val]}]}" ]; then
                			if [ "${feature_values[$x,${chars[$char_val]}]}" == "true" ]; then
                                        	feature_values[$x,${chars[$char_val]}]=false
					fi
                                        k=`expr $k + 1`
                                else
                                        break
                                fi
                        done
		else
                	feature_values[$x,0]=false
                        k=1
                        while [ ${feature_values[$x,0]} ]
                        do
                		char_val=`expr $k - 1`
                                if [ ! -z "${feature_values[$x,${chars[$char_val]}]}" ]; then
                			if [ "${feature_values[$x,${chars[$char_val]}]}" == "true" ]; then
                                        	feature_values[$x,${chars[$char_val]}]=false
					fi
                                        k=`expr $k + 1`
                                else
                                        break
                                fi
                        done
		fi
        else
            if [ "${feature_values[$x,0]}" == "false" ]; then
                   feature_values[$x,0]=true
	    else
                   feature_values[$x,0]=false
            fi
        fi
done
else
if [[ $RESP == *.* ]] ; then
		ValidateSubOption $RESP
		if [ $? -eq 1 ]; then 
			return 1 
		fi
	resp=`echo $RESP | sed -e 's/\./,/'`
	ret=`echo $resp | cut -d "," -f1`
        if [ "${dcism_sections[$ret,0]}" == "$SSO_OPTION" ]; then
			flag=false
			k=1
			while true
                	do
                		char_val=`expr $k - 1`
                        	if [ ! -z "${dcism_sections[$ret,${chars[$char_val]}]}" ]; then
								 if [ "$resp" == "$ret,${chars[$char_val]}" ]; then
										if [ "${feature_values[$resp]}" == "false" ]; then
												feature_values[$resp]=true
												flag=true
										else
												feature_values[$resp]=false
										fi
								 elif [ ! -z "${dcism_sections[$ret,${chars[$char_val]}]}" ]; then
												feature_values[$ret,${chars[$char_val]}]=false
								 fi
								 k=`expr $k + 1`
                        	else
                                	 break
                        	fi
                	done
		if [ "$flag" == "false" ]; then
                        feature_values[$ret,0]=false
                else
                        feature_values[$ret,0]=true
		fi
        elif [ "${dcism_sections[$resp]}" == "$HISTORIC_STR" ]; then #setting the value for Periodic log feature.
                if [ "${feature_values[$resp]}" == "false" ]; then
                        feature_values[$resp]=true
                        feature_values[$ret,0]=true
                else
                        feature_values[$resp]=false
                fi
		else
			if [ "${dcism_sections[$resp]}" == "$SNMP_OMSA_TRAPS_STR" ]; then
				if [ "${feature_values[$resp]}" == "false" ]; then
                        feature_values[$resp]=true
						feature_values[$ret,0]=true
						for ((i=0; i<$COUNT; i++))
						do
								char_val=`expr $i - 1`
								echo ${dcism_sections[$ret,${chars[$char_val]}]}
								if [ "${dcism_sections[$ret,${chars[$char_val]}]}" == "$SNMP_TRAPS_STR"  ]; then
									feature_values[$ret,${chars[$char_val]}]=true
								fi
						done
                else
                        feature_values[$resp]=false
                fi
		elif [ "${dcism_sections[$resp]}" == "$SNMP_TRAPS_STR" ]; then
				if [ "${feature_values[$resp]}" == "false" ]; then
                        feature_values[$resp]=true
						feature_values[$ret,0]=true
                else
                        feature_values[$resp]=false
						for ((i=0; i<$COUNT; i++))
						do
								char_val=`expr $i - 1`
								if [ "${dcism_sections[$ret,${chars[$char_val]}]}" == "$SNMP_OMSA_TRAPS_STR"  ]; then
									feature_values[$ret,${chars[$char_val]}]=false
								fi
						done
                fi
	else
                if [ "${feature_values[$resp]}" == "false" ]; then
                        feature_values[$resp]=true
                else
                        feature_values[$resp]=false
                fi
			fi
                k=1
				flag=false
                while [ ${feature_values[$ret,0]} ]
                do
                	char_val=`expr $k - 1`
                        if [ ! -z "${feature_values[$ret,${chars[$char_val]}]}" ]; then
                            if [ "${feature_values[$ret,${chars[$char_val]}]}" == "true" ]; then
								flag=true
							fi
                            k=`expr $k + 1`
                        else
                            break
                        fi
                done
				if [ "$flag" == "true" ]; then
                        feature_values[$ret,0]=true
                else
                        feature_values[$ret,0]=false
                fi
	fi
else
        if [ "${dcism_sections[$RESP,0]}" == "$IDRAC_OPTION" ]; then		
                if [ "${feature_values[$RESP,0]}" == "false" ]; then
                        feature_values[$RESP,0]=true
                        k=1
                        while [ ${feature_values[$RESP,0]} ]
                        do
                		char_val=`expr $k - 1`
                                if [ ! -z ${feature_values[$RESP,${chars[$char_val]}]} ]; then
                                        feature_values[$RESP,${chars[$char_val]}]=true
                                        k=`expr $k + 1`
                                else
                                        break
                                fi
                        done
                else
                        feature_values[$RESP,0]=false
                        k=1
                        while [ ${feature_values[$RESP,0]} ]
                        do
                		char_val=`expr $k - 1`
                                if [ ! -z ${feature_values[$RESP,${chars[$char_val]}]} ]; then
                                        feature_values[$RESP,${chars[$char_val]}]=false
                                        k=`expr $k + 1`
                                else
                                        break
                                fi
                        done
                fi
 
        elif [ "${dcism_sections[$RESP,0]}" == "$SSO_OPTION" ]; then
                if [ "${feature_values[$RESP,0]}" == "false" ]; then
                        feature_values[$RESP,0]=true
                        k=1
						char_val=`expr $k - 1`
                        feature_values[$RESP,${chars[$char_val]}]=true
                        k=`expr $k + 1`
                        while [ "${feature_values[$RESP,0]}" ]
                        do
                		char_val=`expr $k - 1`
                                if [ ! -z "${feature_values[$RESP,${chars[$char_val]}]}" ]; then
                                        feature_values[$RESP,${chars[$char_val]}]=false
                                        k=`expr $k + 1`
                                else
                                        break
                                fi
                        done
                else
                        feature_values[$RESP,0]=false
                        k=1
                        while [ ${feature_values[$RESP,0]} ]
                        do
                		char_val=`expr $k - 1`
                                if [ ! -z "${feature_values[$RESP,${chars[$char_val]}]}" ]; then
                                        feature_values[$RESP,${chars[$char_val]}]=false
                                        k=`expr $k + 1`
                                else
                                        break
                                fi
                        done
                fi
        elif [ "${dcism_sections[$RESP,0]}" == "$SMART_STR" ]; then
                if [ "${feature_values[$RESP,0]}" == "false" ]; then
                	feature_values[$RESP,0]=true
                        k=1
                        while [ ${feature_values[$RESP,0]} ]
                        do
                		char_val=`expr $k - 1`
                                if [ ! -z "${feature_values[$RESP,${chars[$char_val]}]}" ]; then
                			if [ "${feature_values[$RESP,${chars[$char_val]}]}" == "true" ]; then
                                        	feature_values[$RESP,${chars[$char_val]}]=false
					fi
                                        k=`expr $k + 1`
                                else
                                        break
                                fi
                        done
		else
                	feature_values[$RESP,0]=false
                        k=1
                        while [ ${feature_values[$RESP,0]} ]
                        do
                		char_val=`expr $k - 1`
                                if [ ! -z "${feature_values[$RESP,${chars[$char_val]}]}" ]; then
                			if [ "${feature_values[$RESP,${chars[$char_val]}]}" == "true" ]; then
                                        	feature_values[$RESP,${chars[$char_val]}]=false
					fi
                                        k=`expr $k + 1`
                                else
                                        break
                                fi
                        done
                fi
        elif [ "${ftr[$RESP,0]}" == "$ALL_FEATURES_STR" ]; then
		if [ "${feature_values[$RESP,0]}" == "false" ]; then
                for ((j=1;j<=$COUNT;j++)) do
                        for ((i=0;i<=$COUNT;i++)) do
							if [ $i -eq 0 ] && [ ! -z "${feature_values[$j,$i]}" ]; then
												feature_values[$j,$i]=true
							else
								char_val=`expr $i - 1`
								if [ ! -z "${ftr[$j,${chars[$char_val]}]}" ]; then
									if [ "${dcism_sections[$j,0]}" == "$SSO_OPTION" ]; then
										 feature_values[$j,0]=true
										 if [ "${dcism_sections[$j,${chars[$char_val]}]}" == "$READ_ONLY_OPTION" ]; then
												feature_values[$j,${chars[$char_val]}]=true
										else
												feature_values[$j,${chars[$char_val]}]=false
										fi
									else
										feature_values[$j,${chars[$char_val]}]=true
									fi
								fi
							fi
                        done
                done
	else
                for ((j=1;j<=$COUNT;j++)) do
                        for ((i=0;i<=$COUNT;i++)) do
							if [ $i -eq 0 ] && [ ! -z "${feature_values[$j,$i]}" ]; then
												feature_values[$j,$i]=false
							else
								char_val=`expr $i - 1`
								if [ ! -z "${ftr[$j,${chars[$char_val]}]}" ]; then
										feature_values[$j,${chars[$char_val]}]=false
								fi
							fi
                        done
                done
	fi
        else
                if [ "${feature_values[$RESP,0]}" == "false" ]; then
                	feature_values[$RESP,0]=true
		else
                	feature_values[$RESP,0]=false
		fi
        fi
fi
fi
flag=true
for ((j=1;j<=$COUNT;j++)) do
    for ((i=0;i<=$COUNT;i++)) do
	if [ $i -eq 0 ] && [ ! -z "${feature_values[$j,$i]}" ]; then
                if [ "${feature_values[$j,$i]}" == "false" ]; then
                        flag=false
			break
                fi
	fi
    done
done
if [ "$flag" == "false" ]; then
feature_values[$FEATURE_COUNT,0]=false
else
feature_values[$FEATURE_COUNT,0]=true
fi
return 0
}

function TakeUsersInputOnOptions
{
    if [ $FIRST_SCREEN == 0 ]
    then
    cat <<EOF
  Enter the number to select/deselect a feature from the above list.
		( multiple feature selection should be comma separated)
		( to select sub-features, please use 4.a,4.b, etc.)
  Enter q to quit.

EOF
    elif [ $FIRST_SCREEN == 1 ]
    then
    cat <<EOF
  Enter the number to select/deselect a feature
        ( multiple feature selection should be comma separated)
		( to select sub-features, please use 4.a,4.b, etc.)
  Enter i to install the selected features.
  Enter q to quit.

EOF
   else
        #Handle modify, uninstall and upgrade here
   cat <<EOF

  Enter the number to select/deselect a feature
        ( multiple feature selection should be comma separated)
		( to select sub-features, please use 4.a,4.b, etc.)
  Enter d to uninstall the component.
  Enter q to quit.

EOF

    fi

    opt_pkg_index=`Prompt "  Enter : "`
    # check if number
     if [ $opt_pkg_index -le $FEATURE_COUNT ] 2> /dev/null
     then	     
        ValidateUserSelection $opt_pkg_index
        if [ $? == 0 ]; then
            FIRST_SCREEN=1
            CLEAR_CONTINUE="yes"
            SetInput $opt_pkg_index
		else
            echo "Unknown option."
	    echo "Press any key to continue..."
	    read
	    CLEAR_CONTINUE="yes"
        fi
     elif [[ $opt_pkg_index == *,* ]] ; then
             opt_pkg_index=`echo "$opt_pkg_index" | tr 'A-Z' 'a-z'`             
             FIRST_SCREEN=1
             CLEAR_CONTINUE="yes"
             SetInput "$opt_pkg_index"
             if [ $? == 1 ]; then
            echo "Unknown option."
	    echo "Press any key to continue..."
	    read
	    CLEAR_CONTINUE="yes"
             fi
     elif [[ $opt_pkg_index == *.* ]] ; then
             opt_pkg_index=`echo "$opt_pkg_index" | tr 'A-Z' 'a-z'`             
             FIRST_SCREEN=1
             CLEAR_CONTINUE="yes"
             SetInput "$opt_pkg_index"
             if [ $? == 1 ]; then
            echo "Unknown option."
	    echo "Press any key to continue..."
	    read
	    CLEAR_CONTINUE="yes"
             fi
     else
	if [[ "$opt_pkg_index" =~ ^[0-9]+$ ]]
	then
        ValidateUserSelection $opt_pkg_index
        if [ $? != 0 ]; then
            echo "Unknown option."
	    echo "Press any key to continue..."
	    read
	    CLEAR_CONTINUE="yes"
	fi
	else
        opt_pkg_index=`echo "$opt_pkg_index" | tr 'a-z' 'A-Z'`
        if [ "$opt_pkg_index" == "Q" ]; then
            kill -EXIT $$
            sleep 1
            exit 2
        elif [ "$opt_pkg_index" == "D" ]; then
            #  UnInstallPackages
               CLEAR_CONTINUE="no"
                #"${SERVICES_SCRIPT}" stop
				#log to MUTlogger during uninstall
				setMUTlog 1
				CheckOSType
				if [ $? -eq 0 ]; then
                    rpm -e dcism 2>/tmp/ism.err
					if [ $? -ne 0 ]; then
						cat /tmp/ism.err
						echo "Failed to uninstall iSM rpm .. Exiting !!"
						exit $UNINSTALL_FAILED
					fi
					rpm -q dcism-osc &> /dev/null
					if [ $? -eq 0 ]; then
						rpm -e dcism-osc 2>/tmp/osc.err
						if [ $? -ne 0 ]; then
							cat /tmp/osc.err
							echo "Failed to uninstall OSC rpm .. Exiting !!"
							exit $UNINSTALL_FAILED
						fi
					fi
				else
                    dpkg -P dcism 2>/tmp/ism.err >/dev/null
					if [ $? -ne 0 ]; then
						cat /tmp/ism.err
						echo "Failed to uninstall iSM debian .. Exiting !!"
						exit $UNINSTALL_FAILED
					fi
					if [ $(dpkg-query -W -f='${Status}' dcism-osc 2>/dev/null | grep -c "ok installed") -eq 1 ]; then
						dpkg -P dcism-osc 2>/tmp/osc.err >/dev/null
						if [ $? -ne 0 ]; then
							cat /tmp/osc.err
							echo "Failed to uninstall OSC debian .. Exiting !!"
							exit $UNINSTALL_FAILED
						fi
					fi
				fi
            ldconfig >> /dev/null 2>&1
			if [ -f /tmp/ism.err ]; then
				rm -f /tmp/ism.err
			fi
			if [ -f /tmp/osc.err ]; then
				rm -f /tmp/osc.err
			fi
            exit 0
        elif [ "$opt_pkg_index" == "I" ]; then
            #  InstallPackages
                        CLEAR_CONTINUE="no"
					#check for install/upgrade for mutlogger
				if [ $UPGRADE -ne 1 ]; then
					setMUTlog 0 #install
				else
					setMUTlog 2 #upgrade
				fi
            if [ $MODIFY -ne 1 ]; then
				CheckOSType
				if [ $? -eq 0 ]; then 
						#check osc pkg already installed
						osc_rpm_path=`ls $SYSIDFILEPATH/OSC/dcism-osc-*.rpm`
						osc_pkg_name=$(basename -s .rpm $osc_rpm_path)
						rpm -q $osc_pkg_name 2>/tmp/osc.err
						if [  $? -ne 0 ]; then
							rpm -Uvh "$SYSIDFILEPATH/OSC/dcism*.rpm" 2>/tmp/osc.err
							if [  $? -ne 0 ]; then
								cat /tmp/osc.err
								echo "Error installing OSC rpm... Exiting !!"
								exit $UPDATE_FAILED
							fi 
						fi
						rpm -Uvh "$SYSIDFILEPATH/$GBL_OS_TYPE_STRING/$ARCH/dcism*.rpm" 2>/tmp/ism.err
						if [  $? -ne 0 ]; then
                    		cat /tmp/ism.err
                    		echo "Error installing iSM rpm... Exiting !!"
							#remove osc package in case of failure
							rpm -e dcism-osc 2>/tmp/osc.err
                    		exit $UPDATE_FAILED
						fi
				else
				# saving previously installed idrac port.

				if [ -f "$OS2IDRAC_INI_FILE" ]; then
					IDRAC_PORT=`grep '^listen_port' $OS2IDRAC_INI_FILE | cut -d "=" -f 2`
				fi
					#OSC debian package installation.
					if [ $(dpkg-query -W -f='${Status}' dcism-osc 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
						dpkg -i "$SYSIDFILEPATH/OSC/`ls $SYSIDFILEPATH/OSC/ | grep -i $GBL_OS_TYPE_STRING`" 2>/tmp/osc.err >/dev/null
						if [  $? -ne 0 ]; then
								cat /tmp/osc.err
								echo "Error installing OSC debian... Exiting !!"
								exit $UPDATE_FAILED
						fi
					fi
					CMD="dpkg-deb -f "$SYSIDFILEPATH/$GBL_OS_TYPE_STRING/$ARCH/`ls $SYSIDFILEPATH/$GBL_OS_TYPE_STRING/$ARCH/ | grep deb`" Depends"
					dependencies_pkgs=`$CMD`
                    IFS=', ' read -r -a dpnd <<< "$dependencies_pkgs"
                    for pkg in "${dpnd[@]}"
                    do
						if [ $(dpkg-query -W -f='${Status}' $pkg 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
							echo "Dependency package $pkg is missing.."
							exit $UPDATE_FAILED
						fi
					done				
                	dpkg -i "$SYSIDFILEPATH/$GBL_OS_TYPE_STRING/$ARCH/`ls $SYSIDFILEPATH/$GBL_OS_TYPE_STRING/$ARCH/ | grep deb`" 2>/tmp/ism.err >/dev/null
			       	if [  $? -ne 0 ]; then
                    		cat /tmp/ism.err
                    		echo "Error installing iSM debian... Exiting !!"
                    		exit $UPDATE_FAILED
                	fi
				fi
            fi
		fi
	fi
	fi

    if [ $CLEAR_CONTINUE == "yes" ]; then
        # clear the screen and start over
        clear
        PrintGreetings
        ShowInstallOptions
        TakeUsersInputOnOptions
    fi

        return 0
}

###############################################################################
# Function : GetPathToScript
#
# extracts the path to the script, this path will be used to locate
# the rpms repository on the CD or on the system
#
###############################################################################

function GetPathToScript ()
{
    # $1 is the path to the script, inluding the script name
    PATH_TO_SCRIPT=$(cd -P -- "$(dirname -- "$0")" && pwd -P)
    SCRIPTNAME=`basename $1`

    CURDIR=`pwd | sed "s/ /\\\ /"`
    cd "$PATH_TO_SCRIPT"
    SYSIDFILEPATH="`pwd | sed "s/ /\\\ /"`"
    LICENSEFILEPATH="$PATH_TO_SCRIPT/prereq/license_agreement.txt"
    cd "$CURDIR"
}

function PerformPrereqChecks
{
   . "$SYSIDFILEPATH/prereq/CheckSystemType.sh" "$SYSIDFILEPATH"

    IsThisSupportedGeneration
    # Check whether a valid system ID is available and is a supported DELL server
    if [ $? != 0 ]; then
           echo "Unsupported system"
           exit $UPDATE_PREREQ_NA
    fi
        ARCH=`uname -m`

    # operating system check
    GetOSType
    if [ "${GBL_OS_TYPE}" = "${GBL_OS_TYPE_UKNOWN}" ] || [ "${GBL_OS_TYPE}" = "${GBL_OS_TYPE_ERROR}" ] || [ $ARCH != "x86_64" ]; then
        # Operating system type is unknown, or an error occurred trying to
        # determine the operating system type. Exit with Error 2
   cat <<EOF
     Unrecognized Operating System or Architecture. This script cannot
     continue with the installation. Select packages from the OS folder in
     the media that closely matches this Operating System to continue
     with the manual install.
EOF
        exit $UPDATE_PREREQ_NA
    fi

        #check whether iSM is already installed
        CheckiSMInstalled
}


function PerformPostInstall
{
#Replace new ini file since config files are not replaced during package upgrade.
if [ $UPGRADE == 1 ]; then
	if [ -f ${ISM_INI_FILE}.rpmnew ]; then
		mv -f ${ISM_INI_FILE}.rpmnew ${ISM_INI_FILE} 2>/dev/null
	fi
	if [ -f ${OS2IDRAC_INI_FILE}.rpmnew ]; then
		mv -f ${OS2IDRAC_INI_FILE}.rpmnew ${OS2IDRAC_INI_FILE} 2>/dev/null
	fi

	#need to reset the value to false after upgrade
	ChangeINIKeyValue "${ISM_INI_FILE}" "SupportAssist" "saeulaaccepted" "false"

fi

# stop service if modify
if [ $MODIFY -eq 1 ]; then
	StartStopService stop
fi


#check flag if rpm install was successful
#check whether is installed or not
CheckiSMInstalled
if [ $? -eq 0 ]
then
	#always set this parameter to false
	ChangeINIKeyValue "${ISM_INI_FILE}" "Agent Manager" "InstallerConsumed.enabled" "false"
	if [ ! -z "${MOD_CM}" ]; then
		if [ $PREDEFINE_OPTION -eq 1 -a $MODIFY -eq 1 ]; then
			GetFeaturesEnabledFromINI
		elif [ $PREDEFINE_OPTION -eq 1 ]; then
			GetFeaturesEnabledFromINI
		fi
	fi

	COUNT=${#ftr[@]}
        for ((j=1;j<=$COUNT;j++)) do
         for ((i=0;i<=$COUNT;i++)) do
		 if [ $i -eq 0 ] && [ ! -z ${feature_values[$j,$i]} ]; then
				if [ "$EXPRESS" == "true" ] && [ "${dcism_sections[$j,$i]}" != "$METRICINJECTION_STR" ] && [ "${dcism_sections[$j,$i]}" != "$OS2IDRAC" ] && [ "${dcism_sections[$j,$i]}" != "$SNMP_TRAPS_STR" ] && [ "${dcism_sections[$j,$i]}" != "$SNMP_OMSA_TRAPS_STR" ] && [ "${dcism_sections[$j,$i]}" != "$SNMPGET_STR" ] && [ "${dcism_sections[$j,$i]}" != "$ADMIN_OPTION" ]; then
					feature_values[$j,$i]=true
				fi
				
				if [ "${dcism_sections[$j,$i]}" == "$SMART_STR" ] && [ "${feature_values[$j,$i]}" == "true" ]; then
					if [ $MODIFY -eq 1 ]; then
                        sata_status=`/opt/dell/srvadmin/iSM/bin/Invoke-iSMPKIHelper -getControllerMode`
                        if [ $sata_status -eq 0 ]; then
                                ChangeINIKeyValue "${ISM_INI_FILE}" "${dcism_sections[$j,$i]}" "feature.enabled" "true"
                        else
                                ChangeINIKeyValue "${ISM_INI_FILE}" "${dcism_sections[$j,$i]}" "feature.enabled" "false"
                        fi
					else
						continue
					fi
				else
					ChangeINIKeyValue "${ISM_INI_FILE}" "${dcism_sections[$j,$i]}" "feature.enabled" "${feature_values[$j,$i]}"
				fi
		else
			char_val=`expr $i - 1`
			if [ ! -z "${ftr[$j,${chars[$char_val]}]}" ]; then
				if [ "${dcism_sections[$j,${chars[$char_val]}]}" == "$SNMP_TRAPS_STR" ]; then
					if [ "${feature_values[$j,${chars[$char_val]}]}" == "true" ]; then
						${SNMPTRAP_SCRIPT} enable >> /dev/null 2>&1
					else
						${SNMPTRAP_SCRIPT} disable >> /dev/null 2>&1
						ChangeINIKeyValue "${ISM_INI_FILE}" "${dcism_sections[$j,${chars[$char_val]}]}" "feature.omsaAlertForward" "false"
						ChangeINIKeyValue "${ISM_INI_FILE}" "${dcism_sections[$j,${chars[$char_val]}]}" "feature.enabled" "false"
					fi
				fi				
				if [ "$EXPRESS" == "true" ] && [ "${dcism_sections[$j,$i]}" != "$METRICINJECTION_STR" ] && [ "${dcism_sections[$j,${chars[$char_val]}]}" != "$OS2IDRAC" ] && [ "${dcism_sections[$j,${chars[$char_val]}]}" != "$SNMP_TRAPS_STR" ] && [ "${dcism_sections[$j,${chars[$char_val]}]}" != "$SNMP_OMSA_TRAPS_STR" ]  && [ "${dcism_sections[$j,${chars[$char_val]}]}" != "$SNMPGET_STR" ] && [ "${dcism_sections[$j,${chars[$char_val]}]}" != "$ADMIN_OPTION" ]; then
						feature_values[$j,${chars[$char_val]}]=true
				fi
				# set the feature omsa snmp traps logs value to dcismdy64.ini
				if [ "${dcism_sections[$j,${chars[$char_val]}]}" == "$SNMP_OMSA_TRAPS_STR" ]; then
					if [ "${feature_values[$j,${chars[$char_val]}]}" == "true" ]; then
						for ((k=0; k<$COUNT; k++))
						do
								char_val=`expr $k - 1`
								if [ "${dcism_sections[$j,${chars[$char_val]}]}" == "$SNMP_TRAPS_STR"  ]; then
									ChangeINIKeyValue "${ISM_INI_FILE}" "${dcism_sections[$j,${chars[$char_val]}]}" "feature.omsaAlertForward" "true"
								fi
						done
					else
						for ((k=0; k<$COUNT; k++))
						do
								char_val=`expr $k - 1`
								if [ "${dcism_sections[$j,${chars[$char_val]}]}" == "$SNMP_TRAPS_STR"  ]; then
									ChangeINIKeyValue "${ISM_INI_FILE}" "${dcism_sections[$j,${chars[$char_val]}]}" "feature.omsaAlertForward" "false"
								fi
						done
					fi
				fi
				# set the feature Periodic logs value to dccs.ini, if server is 14G and above.
				if [ "${dcism_sections[$j,${chars[$char_val]}]}" == "$HISTORIC_STR" ] && [ $server_gen -ge 14 ]; then
					if [ "${dcism_sections[$j,0]}" == "$SMART_STR" ] && [ "${feature_values[$j,0]}" == "true" ]; then
						if [ $MODIFY -eq 1 ]; then
                            sata_status=`/opt/dell/srvadmin/iSM/bin/Invoke-iSMPKIHelper -getControllerMode`
                            if [ $sata_status -eq 0 ] && [ "${feature_values[$j,${chars[$char_val]}]}" == "true" ]; then
                                    ChangeINIKeyValue "${DCCS_INI_FILE}" "${dcism_sections[$j,${chars[$char_val]}]}" "feature.enabled" "true"
                            else
                                    ChangeINIKeyValue "${DCCS_INI_FILE}" "${dcism_sections[$j,${chars[$char_val]}]}" "feature.enabled" "false"
                            fi
						else
							if [ "${feature_values[$j,${chars[$char_val]}]}" == "false" ]; then
								ChangeINIKeyValue "${DCCS_INI_FILE}" "${dcism_sections[$j,${chars[$char_val]}]}" "feature.enabled" "${feature_values[$j,${chars[$char_val]}]}"
							fi
						fi
					else
							ChangeINIKeyValue "${DCCS_INI_FILE}" "${dcism_sections[$j,${chars[$char_val]}]}" "feature.enabled" "false"
					fi
				fi
				
				if [ "${dcism_sections[$j,${chars[$char_val]}]}" != "$OS2IDRAC" ]; then
						ChangeINIKeyValue "${ISM_INI_FILE}" "${dcism_sections[$j,${chars[$char_val]}]}" "feature.enabled" "${feature_values[$j,${chars[$char_val]}]}"
				fi
			fi
		fi
	 done
	done

	#if this is a silent install
	if [ ! -z "${MOD_CM}" ]
	then
	COUNT=${#ftr[@]}
        for ((j=1;j<=$COUNT;j++)) do
         for ((i=0;i<=$COUNT;i++)) do
		 if [ $i -eq 0 ]; then
			 continue
		 else
			char_val=`expr $i - 1`
			if [ ! -z "${feature_values[$j,${chars[$char_val]}]}" ]; then
				if [ "${dcism_sections[$j,${chars[$char_val]}]}" == "$OS2IDRAC" ] && [ "${feature_values[$j,${chars[$char_val]}]}" == "true" ]; then
					ChangeINIKeyValue "${OS2IDRAC_INI_FILE}" "OS2iDRAC" "listen_port" "$OS2IDRAC_PORT_NUM"
				fi
				if [ "${dcism_sections[$j,${chars[$char_val]}]}" == "$READ_ONLY_OPTION" ] || [ "${dcism_sections[$j,${chars[$char_val]}]}" == "$ADMIN_OPTION" ]; then 
					enabled_option=`sed -n '/enabled=/p' $DCISM_IDRAC_LAUNCHER_INI`
					privilege=`sed -n '/privilege=/p' $DCISM_IDRAC_LAUNCHER_INI`
					if [ "${dcism_sections[$j,${chars[$char_val]}]}" == "$READ_ONLY_OPTION" ] && [ "${feature_values[$j,${chars[$char_val]}]}" == "true" ]; then
						sed -i "s/$enabled_option/enabled=true/g" $DCISM_IDRAC_LAUNCHER_INI
						sed -i "s/$privilege/privilege=1/g" $DCISM_IDRAC_LAUNCHER_INI
					elif [ "${dcism_sections[$j,${chars[$char_val]}]}" == "$ADMIN_OPTION" ] && [ "${feature_values[$j,${chars[$char_val]}]}" == "true" ]; then 
						sed -i "s/$enabled_option/enabled=true/g" $DCISM_IDRAC_LAUNCHER_INI
						sed -i "s/$privilege/privilege=2/g" $DCISM_IDRAC_LAUNCHER_INI
					elif [ "${dcism_sections[$j,0]}" == "$SSO_OPTION" ] && [ "${feature_values[$j,0]}" == "false" ]; then
						sed -i "s/$enabled_option/enabled=false/g" $DCISM_IDRAC_LAUNCHER_INI
						sed -i "s/$privilege/privilege=3/g" $DCISM_IDRAC_LAUNCHER_INI
					fi
				fi
			fi
		fi
	 done
	done
		if [ $AUTO_START == "true" ]
		then
			ldconfig >> /dev/null 2>&1
			#"${SERVICES_SCRIPT}" start
			StartStopService start
		fi
	else
	COUNT=${#ftr[@]}
        for ((j=1;j<=$COUNT;j++)) do
         for ((i=0;i<=$COUNT;i++)) do
		 if [ $i -eq 0 ]; then
			 continue
		 else
			char_val=`expr $i - 1`
		if [ ! -z "${ftr[$j,${chars[$char_val]}]}" ]; then
        # port input for iDRAC access via Host OS
        if [ "${dcism_sections[$j,${chars[$char_val]}]}" == "$OS2IDRAC" ] && [ "${feature_values[$j,${chars[$char_val]}]}" == "true" ]; then
            while true
            do
				LISTENPORT=`grep '^listen_port' "${OS2IDRAC_INI_FILE}" | cut -d "=" -f 2`
				if [ ! -z "$IDRAC_PORT" ]; then
					LISTENPORT="$IDRAC_PORT"
				fi
	        echo ""
                read -e -i "$LISTENPORT" -p "Enter a valid port number for iDRAC access via Host OS or Enter to take default port number: " PORT_NUM

                    if [[ $PORT_NUM =~ ^[0-9]+$ ]] && (( $PORT_NUM > 1023 )) && (( $PORT_NUM < 65536 ))
                    then
                        echo ""
                        ChangeINIKeyValue "${OS2IDRAC_INI_FILE}" "OS2iDRAC" "listen_port" "$PORT_NUM"
                        break
                    else
                        LISTENPORT=`grep '^listen_port' "${OS2IDRAC_INI_FILE}" | cut -d "=" -f 2`
                        IANAPORT=`grep '^iana_default_port' "${OS2IDRAC_INI_FILE}" | cut -d "=" -f 2`
                        if [ ! -z $LISTENPORT ] && [ -z $PORT_NUM ]
                        then
                            echo ""
                            break
                        elif [ ! -z $IANAPORT ] && [ -z $PORT_NUM ]
                        then
                            if [[ $IANAPORT =~ ^[0-9]+$ ]] && (( $IANAPORT > 1023 )) && (( $IANAPORT < 65536 ))
                            then
                                echo ""
                                ChangeINIKeyValue "${OS2IDRAC_INI_FILE}" "OS2iDRAC" "listen_port" "$IANAPORT"
                                break
                            fi
                        fi
                        PORT_NUM=""
                    fi
                    echo "Port number is invalid or default port number is not configured"
            done
        elif [ "${dcism_sections[$j,${chars[$char_val]}]}" == "$OS2IDRAC" ] && [ "${feature_values[$j,${chars[$char_val]}]}" == "false" ]; then
            # The below code is added to disable IBIA feature when the feature is de-selected during Upgrade
            	ChangeINIKeyValue "${OS2IDRAC_INI_FILE}" "OS2iDRAC" "enabled" ""
            	ChangeINIKeyValue "${OS2IDRAC_INI_FILE}" "OS2iDRAC" "listen_port" ""
        fi





		if [ -e $DCISM_IDRAC_LAUNCHER_INI ]; then
			enabled_option=`sed -n '/enabled=/p' $DCISM_IDRAC_LAUNCHER_INI`
			privilege=`sed -n '/privilege=/p' $DCISM_IDRAC_LAUNCHER_INI`
			if [ "${dcism_sections[$j,${chars[$char_val]}]}" == "$READ_ONLY_OPTION" ] && [ "${feature_values[$j,${chars[$char_val]}]}" == "true" ]; then
				sed -i "s/$enabled_option/enabled=true/g" $DCISM_IDRAC_LAUNCHER_INI
				sed -i "s/$privilege/privilege=1/g" $DCISM_IDRAC_LAUNCHER_INI
			elif [ "${dcism_sections[$j,${chars[$char_val]}]}" == "$ADMIN_OPTION" ] && [ "${feature_values[$j,${chars[$char_val]}]}" == "true" ]; then
				sed -i "s/$enabled_option/enabled=true/g" $DCISM_IDRAC_LAUNCHER_INI
				sed -i "s/$privilege/privilege=2/g" $DCISM_IDRAC_LAUNCHER_INI
			elif [ "${dcism_sections[$j,0]}" == "$SSO_OPTION" ] && [ "${feature_values[$j,0]}" == "false" ]; then
				sed -i "s/$enabled_option/enabled=false/g" $DCISM_IDRAC_LAUNCHER_INI
				sed -i "s/$privilege/privilege=3/g" $DCISM_IDRAC_LAUNCHER_INI
			fi
		fi
	fi
fi
done
done
		cat <<EOF

Do you want the services started?



EOF
		sa_start=`Prompt "   Press ('y' for yes | 'Enter' to exit): "`

		# now start if 'yes'
		if echo "${sa_start}" | grep -qi "^y$" ; then

			ldconfig >> /dev/null 2>&1
			#"${SERVICES_SCRIPT}" start
			StartStopService start
			echo ""
		fi
	fi
fi
}

function UpdateOS2IDRACPortFromINIFile {

    if [ "${OS2IDRAC_ENABLED}" == "true" ] && [ $OS2IDRAC_PORT_NUM -eq 0 ]
    then
            LISTENPORT=`grep '^listen_port' "${OS2IDRAC_INI_FILE}" | cut -d "=" -f 2`
            IANAPORT=`grep '^iana_default_port' "${OS2IDRAC_INI_FILE}" | cut -d "=" -f 2`
        if [ -z $LISTENPORT ]; then
            OS2IDRAC_PORT_NUM=$IANAPORT
        else
            OS2IDRAC_PORT_NUM=$LISTENPORT
        fi
    fi
}

#UpdateOS2IDRACPortFromINIFile function is called two places at modify and upgrade case.
function InstallPackageSilent
{
    # if port is specified make sure OS2IDRAC is specified too
    if [ "${OS2IDRAC_ENABLED}" == "false" ] && [ $OS2IDRAC_PORT_NUM -ne 0 ]
    then
        echo "Invalid Options, please see the usage below"
        Usage
    fi

    CheckiSMInstalled
    if [ $? != 0 ] || [ $UPGRADE == 1 ]; then
	CheckOSType
        if [ $? -eq 0 ]; then
			#check osc pkg already installed
			osc_rpm_path=`ls $SYSIDFILEPATH/OSC/dcism-osc-*.rpm`
			osc_pkg_name=$(basename -s .rpm $osc_rpm_path)
			rpm -q $osc_pkg_name 2>/tmp/osc.err
			if [  $? -ne 0 ]; then
				rpm -Uvh "$SYSIDFILEPATH/OSC/dcism*.rpm" 2>/tmp/osc.err
				if [  $? -ne 0 ]; then
					cat /tmp/osc.err
					echo "Error installing OSC rpm... Exiting !!"
					exit $UPDATE_FAILED
				fi
			fi
        	rpm -Uvh "$SYSIDFILEPATH/$GBL_OS_TYPE_STRING/$ARCH/dcism*.rpm" 2>/tmp/ism.err
            if [  $? -ne 0 ]; then
                cat /tmp/ism.err
                echo "Error installing iSM rpm... Exiting !!"
				#remove osc package in case of failure
				rpm -e dcism-osc 2>/tmp/osc.err
                exit $UPDATE_FAILED
            fi
        else
			#OSC debian package installation.
			if [ $(dpkg-query -W -f='${Status}' dcism-osc 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
				dpkg -i "$SYSIDFILEPATH/OSC/`ls $SYSIDFILEPATH/OSC/ | grep deb`" 2>/tmp/osc.err >/dev/null
			    if [  $? -ne 0 ]; then
                    cat /tmp/osc.err
                    echo "Error installing OSC debian... Exiting !!"
                    exit $UPDATE_FAILED
				fi
			fi
			CMD="dpkg-deb -f "$SYSIDFILEPATH/$GBL_OS_TYPE_STRING/$ARCH/`ls $SYSIDFILEPATH/$GBL_OS_TYPE_STRING/$ARCH/ | grep deb`" Depends"
			dependencies_pkgs=`$CMD`
			IFS=', ' read -r -a dpnd <<< "$dependencies_pkgs"
			for pkg in "${dpnd[@]}"
			do
				if [ $(dpkg-query -W -f='${Status}' $pkg 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
					echo "Dependency package $pkg is missing.."
					exit $UPDATE_FAILED
				fi
			done
            dpkg -i "$SYSIDFILEPATH/$GBL_OS_TYPE_STRING/$ARCH/`ls $SYSIDFILEPATH/$GBL_OS_TYPE_STRING/$ARCH/ | grep deb`" 2>/tmp/ism.err
            if [  $? -ne 0 ]; then
                 cat /tmp/ism.err
                echo "Error installing iSM debian... Exiting !!"
                exit $UPDATE_FAILED
            fi
		fi
        UpdateOS2IDRACPortFromINIFile
        PerformPostInstall
    elif [ $MODIFY -eq 1 ]; then
        UpdateOS2IDRACPortFromINIFile
        PerformPostInstall
    else
        echo "Service Module already installed"
        exit $UPDATE_NOT_REQD
    fi

}

function StartStopService 
{
operation=$1
systemctl $operation dcismeng.service >> /dev/null 2>&1
result=$?
# stop does not require error check
if [ "$operation" != "stop" ] && [ $result -ne 0 ]; then
	echo "Failed to $operation the iSM service .. Exiting !!"
	exit $SERVICE_FAILED_TO_START
fi
if [ "$operation" == "start" ]; then
        CheckUSBNIC
fi
}

function UninstallPackageSilent
{
#"${SERVICES_SCRIPT}" stop
	#log to MUT logger during silent uninstall
	setMUTlog 1
	CheckOSType
    if [ $? -eq 0 ]; then
        rpm -e dcism 2>/tmp/ism.err
        if [ $? -ne 0 ]; then
            cat /tmp/ism.err
            echo "Failed to uninstall iSM rpm .. Exiting !!"
            exit $UNINSTALL_FAILED
        fi
		rpm -q dcism-osc &> /dev/null
		if [ $? -eq 0 ]; then
			rpm -e dcism-osc 2>/tmp/osc.err
			if [ $? -ne 0 ]; then
				cat /tmp/osc.err
				echo "Failed to uninstall OSC rpm .. Exiting !!"
				exit $UNINSTALL_FAILED
			fi
		fi
    else
        dpkg -P dcism 2>/tmp/ism.err >/dev/null
        if [ $? -ne 0 ]; then
            cat /tmp/ism.err
            echo "Failed to uninstall iSM debian .. Exiting !!"
            exit $UNINSTALL_FAILED
        fi
		dpkg -P dcism-osc 2>/tmp/osc.err >/dev/null
        if [ $? -ne 0 ]; then
            cat /tmp/osc.err
            echo "Failed to uninstall OSC debian .. Exiting !!"
            exit $UNINSTALL_FAILED
        fi
    fi
	ldconfig >> /dev/null 2>&1
	if [ -f /tmp/ism.err ]; then
		rm -f /tmp/ism.err
	fi
	if [ -f /tmp/osc.err ]; then
		rm -f /tmp/osc.err
	fi
}

#Check USB NIC communication status
function CheckUSBNIC
{
	COUNTER=0
	ConnectStatus=0
	newlineCounter=0
       	echo "  Checking for iSM communication with iDRAC..."	
       	echo -ne "    Waiting..."	
       	echo -ne "			"	
        while [  $COUNTER -lt 12 ]; do
             /opt/dell/srvadmin/iSM/bin/dchosmicli 0 3 > /dev/null
	     if [ $? -eq 0 ];then
		let ConnectStatus=ConnectStatus+1
	     	echo -ne " [100%]"
		break
	     fi
	     let newlineCounter=newlineCounter+1
             let COUNTER=COUNTER+1
	     if [ $newlineCounter -gt 6 ]; then
		newlineCounter=0
		echo ""
       		echo -ne "			        "	
	     fi
	     echo -ne "#####"
             pid=`pidof dsm_ism_srvmgrd`
	     if [  -z "$pid" ]; then
		break
	     fi		 
	     sleep 10 
        done
	echo ""
	if [ $ConnectStatus -eq 0 ];then
	
            echo "  iSM is unable to communicate with iDRAC. Please refer the FAQs section in Install Guide."
	else	
            echo "  iSM communication with iDRAC is established successfully."
	fi
} #CheckUSBNIC

#function to get iSM version to be installed.
function getVersion
{
	CheckOSType
	if [ $? -eq 0 ]; then
		ISM_VERSION=`rpm -qp "$SYSIDFILEPATH/$GBL_OS_TYPE_STRING/$ARCH/dcism*.rpm" --qf "%{version}"`        
    else
		if [ -d $SYSIDFILEPATH/$GBL_OS_TYPE_STRING/$ARCH ]; then
			CMD="dpkg-deb -f "$SYSIDFILEPATH/$GBL_OS_TYPE_STRING/$ARCH/`ls $SYSIDFILEPATH/$GBL_OS_TYPE_STRING/$ARCH/ | grep deb`" Version"
			ISM_VERSION=`$CMD`
		fi
    fi
}

#function to log in mutlogger, gets arguements a 0-Install,1-Uninstall,2-Upgrade
function setMUTlog
{
	opt=() # array to collect enabled features in long options formats
     COUNT=${#ftr[@]}
    for ((j=1;j<=$COUNT;j++)) do
    for ((i=0;i<=$COUNT;i++)) do
	    if [ $i -eq 0 ] && [ ! -z "${feature_values[$j,$i]}" ]; then
        		if [ "${ftr[$j,$i]}" != "$ALL_FEATURES_STR" ] && [ "${dcism_sections[$j,$i]}" != "$IDRAC_OPTION" ]; then
					echo "${feature_values[$j,$i]}" | grep -i "true" > /dev/null 2>&1
					if [ $? -eq 0 ]; then
						if [ "${dcism_sections[$j,$i]}" == "$OS2IDRAC" ]; then
							opt+=("OS2iDRAC")
						elif [ "${ftr[$j,$i]}" == "$IDRAC_HARD_RESET_STR" ]; then
							opt+=("iDRACHardReset")
						else
							opt+=("${long_opts[$j,$i]}")
						fi
					fi
			fi
	    else
		    char_val=`expr $i - 1`
			if [ ! -z "${ftr[$j,${chars[$char_val]}]}" ]; then
				if [ "${ftr[$j,${chars[$char_val]}]}" != "$ALL_FEATURES_STR" ] && [ "${dcism_sections[$j,${chars[$char_val]}]}" != "$IDRAC_OPTION" ]; then
						echo "${feature_values[$j,${chars[$char_val]}]}" | grep -i "true" > /dev/null 2>&1
						if [ $? -eq 0 ]; then
								if [ "${dcism_sections[$j,${chars[$char_val]}]}" == "$OS2IDRAC" ]; then
										opt+=("OS2iDRAC")
								elif [ "${ftr[$j,${chars[$char_val]}]}" == "$IDRAC_HARD_RESET_STR" ]; then
										opt+=("iDRACHardReset")
								else
										opt+=("${long_opts[$j,${chars[$char_val]}]}")
								fi
						fi
				fi

			fi
	    fi
    done
    done
	if [ "$ID" == "centos" ]; then
		OS_TYPE="CENTOS"
	elif [ "$ID" == "ahv" ]; then
		OS_TYPE="AHV"
	else
		OS_TYPE=$GBL_OS_TYPE_STRING
	fi
    enbld_opts=$(IFS=,;echo "${opt[*]}")
	getVersion
    if [ $1 -eq 0 ]; then #for install
        echo "Install$ISM_VERSION os=$OS_TYPE.install:$enbld_opts:remove:null,installmethod=webpack" > $MUT_LOG_FILE
    elif [ $1 -eq 1 ]; then #for uninstall
        echo "Remove$ISM_VERSION os=$OS_TYPE.install:null:remove:$enbld_opts,installmethod=webpack" > $MUT_LOG_FILE
    else
        echo "Upgrade$ISM_VERSION os=$OS_TYPE.install:$enbld_opts,installmethod=webpack" > $MUT_LOG_FILE #for upgrade
    fi
}

#function to retrieve the SATA controller status.
function GetSATAValue
{
	if [ -d prereq/racadmpassthru/$GBL_OS_TYPE_STRING ]; then
		pushd prereq/racadmpassthru/$GBL_OS_TYPE_STRING/ >/dev/null
		if [ -f racadmpassthrucli-$PREFIX_FOR_SATA ]; then
			SATA_VALUE=`./racadmpassthrucli-$PREFIX_FOR_SATA "racadm get bios.satasettings.embsata" | grep embsata | awk -F= '{ print $2 }'`
			if [ -z "$SATA_VALUE" ]; then
				SATA_VALUE="Off"
			fi
		fi
		popd >/dev/null
	fi
}

#######################################################
#function:getFeatureStatus
#function to retrieve the status of features other than
#from dcismdy64.ini
#
######################################################
function getFeatureStatus
{
COUNT=${#ftr[@]}
for ((j=1;j<=$COUNT;j++)) do
    for ((i=0;i<=$COUNT;i++)) do
	    char_val=`expr $i - 1`
	    #if [ "${dcism_sections[$j,${chars[$char_val]}]}" == "$SNMP_TRAPS_STR" ]; then
		#	# SNMP TRAPs check
		#	${SNMPTRAP_SCRIPT} status >> /dev/null 2>&1
		#	if [ $? == 0 ]; then
		#		feature_values[$j,${chars[$char_val]}]="true"
		#	else
		#		feature_values[$j,${chars[$char_val]}]="false"
		#	fi
	    #fi
	    if [ "${dcism_sections[$j,0]}" == "$IDRAC_OPTION" ]; then
			if [ "${dcism_sections[$j,${chars[$char_val]}]}" == "$OS2IDRAC" ]; then
				${IBIA_SCRIPT} get-status | grep -i enabled >> /dev/null 2>&1
            			if [ $? == 0 ]; then
                			feature_values[$j,${chars[$char_val]}]="true"
            			else
                			feature_values[$j,${chars[$char_val]}]="false"
            			fi
			fi
                         if [ ! -z "${feature_values[$j,${chars[$char_val]}]}" ]; then
                                 if [ "${feature_values[$j,${chars[$char_val]}]}" == "true" ]; then
                                         flag=true
                                 fi
                         fi
			if [ "$flag" == "true" ]; then
				feature_values[$j,0]="true"
			else
				feature_values[$j,0]="false"
			fi
	    fi
	    if [ "${dcism_sections[$j,0]}" == "$SSO_OPTION" ]; then
	    	if [ -e $DCISM_IDRAC_LAUNCHER_INI ]; then
	    		enabled_option=`grep '^enabled' $DCISM_IDRAC_LAUNCHER_INI | cut -d "=" -f 2`
	    		if [ "$enabled_option" = "true" ]; then
					feature_values[$j,0]="true"
	    		else
					feature_values[$j,0]="false"
	    		fi
	    		if [ "$enabled_option" = "true" ]; then
	    			privilege_option=`grep '^privilege' $DCISM_IDRAC_LAUNCHER_INI | cut -d "=" -f 2`
	    			if [ "$privilege_option" = "1" ] && [ "${dcism_sections[$j,${chars[$char_val]}]}" == "$READ_ONLY_OPTION" ]; then
						feature_values[$j,${chars[$char_val]}]="true"
	    			elif [ "$privilege_option" = "2" ] && [ "${dcism_sections[$j,${chars[$char_val]}]}" == "$ADMIN_OPTION" ]; then
						feature_values[$j,${chars[$char_val]}]="true"
	    			fi
			fi
		else
			if [ $UPGRADE == 1 ]; then
				feature_values[$j,0]="true"
				if [ "${dcism_sections[$j,${chars[$char_val]}]}" == "$READ_ONLY_OPTION" ]; then
                        feature_values[$j,${chars[$char_val]}]="true"
                elif [ "${dcism_sections[$j,${chars[$char_val]}]}" == "$ADMIN_OPTION" ]; then
                        feature_values[$j,${chars[$char_val]}]="false"
                fi
			fi
	    	fi
	    fi
		#check during iSM upgrade, whether the feature entry is present in dcismdy64.ini
            if [ "${dcism_sections[$j,0]}" == "$SMART_STR" ]; then
                smart_value=`GetINIKeyValue "${ISM_INI_FILE}" "${dcism_sections[$j,0]}" "feature.enabled"`
                if [ -z $smart_value ]; then
                        feature_values[$j,0]="true"
                fi
	    fi

		#get the feature Periodic logs value from dccs.ini file in case of modify.
	    if [ "${dcism_sections[$j,${chars[$char_val]}]}" == "$HISTORIC_STR" ]; then
	   	if [ -e $DCCS_INI_FILE ]; then
			periodic_value=`GetINIKeyValue "${DCCS_INI_FILE}" "${dcism_sections[$j,${chars[$char_val]}]}" "feature.enabled"`
            if [ -z $periodic_value ]; then
				if [ "$smart_value" == "true" ]; then
                       	feature_values[$j,${chars[$char_val]}]="true"
				else
						feature_values[$j,${chars[$char_val]}]="false"
				fi
			else
                echo ${periodic_value} | grep -i true > /dev/null 2>&1
                if [ $? -eq 0 ]; then
						feature_values[$j,${chars[$char_val]}]="true"
                else
                        feature_values[$j,${chars[$char_val]}]="false"
                fi
             fi
		else
			#this is to enable Historic logs feature by default in case of iSM verions less than 3.4.1 where SMART was not introduced.
			if [ $UPGRADE == 1 ]; then
                feature_values[$j,${chars[$char_val]}]="true"
            fi
		fi
	    fi
		
		#get feature omsaAlertForward value from dcismdy64.ini file
		
		if [ "${dcism_sections[$j,${chars[$char_val]}]}" == "$SNMP_OMSA_TRAPS_STR" ]; then
			if [ -e $ISM_INI_FILE ]; then
				omsa_trap_value=`GetINIKeyValue "${ISM_INI_FILE}" "$SNMP_TRAPS_STR" "feature.omsaAlertForward"`
				if [ -z "${omsa_trap_value}" ]; then
					feature_values[$j,${chars[$char_val]}]="false"
				else
					feature_values[$j,${chars[$char_val]}]=$omsa_trap_value
				fi
			fi
	    fi
	done
done
flag=true
for ((j=1;j<=`expr $FEATURE_COUNT - 4`;j++)) do
    i=0	
    if [ ! -z "${feature_values[$j,$i]}" ]; then
      if [ "${feature_values[$j,$i]}" == "false" ]; then
	    flag=false
	    break
      fi
    fi
done
if [ "$flag" == "true" ]; then
	feature_values[$FEATURE_COUNT,0]="true"
else
	feature_values[$FEATURE_COUNT,0]="false"
fi
return 0

}

###############################################################
#function: ForRacadmCLI
#this function is used to create ipc directory before
#running racadmpassthrucli command to retirive
#server generation, so that command doesn't fail when
#iSM is upgraded from less than 3.5.1
##############################################################
function ForRacadmCLI
{
    if [ $UPGRADE -eq 1 ]; then
			ISMVERSION="351"
            if [ "$PKG_VER" \< "$ISMVERSION" ]; then
                    if [ ! -d $IPC_DIR ]; then
                            mkdir -p $IPC_DIR > /dev/null 2>&1
                    fi
            fi
    fi
}

###############################################################################
# Function : Main
#
# This is the starting point for the script, this
# function invokes other functions in the required
# order
###############################################################################
function Main
{
    GetOSType
    CheckiSMInstalled

    if [ $? != 0 ]
    then
       PerformPrereqChecks
    fi
	ForRacadmCLI
    GetServerGen
    #Show License if there are no options passed
    if [ -z "$1" ]
    then
       ShowLicense
    fi

	if [ $FEATURES_POPULATED != 1 ]; then
		if [ $UPGRADE == 1 ] || [ $MODIFY == 1 ]; then
			GetFeaturesEnabledFromINI
			getFeatureStatus
		fi
	fi

    # process any options passed
    if [ $# -le 2 ]; then
        if [ "$1" == "-a" -o "$1" == "-i" ] && [ "$2" == "-a" -o "$2" == "-i" ]; then
		    PREDEFINE_OPTION=1
		fi
    fi
    if [ $# -gt 0 ];
    then
      # process options
     ValidateOpts $*
    fi

    # process any options passed
    #as MOD_CM Contains filtered command line options i.e other than --prefix
    if [  -n "${MOD_CM}" ]; then

      # if already installed, should be able to add comps OR upgrade
#      DetectPreviousInstall "silent"

      # install or uninstall
		if [ $SHORT_DEL == "true" ]
		then
				UninstallPackageSilent
		else
			if [ "$SCRIPT_SOURCE" == "sbin" ]; then
				echo "Installer files not found in expected location .. Cannot continue with install options $MOD_CM .. "
				exit $ERROR
			fi
			#check for install/upgrade in silent mode for mutlogger
			if [ $UPGRADE -ne 1 ]; then
                setMUTlog 0 #install
			else
                setMUTlog 2 #upgrade
			fi
			InstallPackageSilent
		fi
    else
      # clear screen and print greetings
            clear
     # PrintGreetings
        PrintGreetings
      # list the optional features that user can choose from
            ShowInstallOptions
      # read users input on the optional packages
            TakeUsersInputOnOptions
          # if the install or upgrade was successful, run post install
                PerformPostInstall
    fi
}

GetPathToScript $0
PATH_TO_SCRIPT=$(cd -P -- "$(dirname -- "$0")" && pwd -P)
EXECUTION_DIR=`pwd | sed "s/ /\\\ /"`
cd "$PATH_TO_SCRIPT"

Main $* 2>&1
cd "$EXECUTION_DIR"

###############################################################################
# Debian/Proxmox udev boot fix
#
# Problem:
#   The dcism package (built for Ubuntu 24) ships /etc/udev/rules.d/95-iSM-usbnic.rules
#   which uses blocking RUN+= directives to invoke /etc/init.d/dcismeng from a udev
#   worker when the iDRAC USB NIC is detected. On Debian 13 / Proxmox 9, this blocks
#   the udev worker for 60+ seconds causing systemd-udev-settle to time out, which
#   in turn delays networking.service and leaves all interfaces down at boot.
#
# Fix:
#   1. Install a systemd oneshot service (dcism-usbnic-hotplug.service) that performs
#      the same two actions as the original udev rules (touch the flag file, start the
#      daemon) but outside the udev worker context.
#   2. Replace the blocking udev rule with a TAG+="systemd" / SYSTEMD_WANTS rule that
#      hands off to the oneshot service asynchronously.
#   3. Use dpkg-divert on the udev rules file so future dcism package upgrades do not
#      silently restore the broken rule.
#
# Tested on: Proxmox VE 9.1 (Debian 13), dcism 5.4.2.0-4048.ubuntu24
###############################################################################

ApplyDebianUdevFix()
{
    # Only apply on Debian-based systems (covers Proxmox)
    if [ ! -f /etc/debian_version ]; then
        return 0
    fi

    echo ""
    echo "Detected Debian-based OS — applying udev boot fix for dcism..."

    UDEV_RULE_FILE="/etc/udev/rules.d/95-iSM-usbnic.rules"
    SYSTEMD_SERVICE_FILE="/etc/systemd/system/dcism-usbnic-hotplug.service"
    USBNIC_FLAG_FILE="/opt/dell/srvadmin/iSM/etc/ini/usbnicconfig.ini"
    DCISMENG_INIT="/etc/init.d/dcismeng"

    # Step 1: Install the systemd oneshot handler service
    cat > "$SYSTEMD_SERVICE_FILE" << 'SERVICEEOF'
[Unit]
Description=Dell iSM USB NIC hotplug handler
After=systemd-udevd.service

[Service]
Type=oneshot
RemainAfterExit=no
ExecStart=/bin/touch /opt/dell/srvadmin/iSM/etc/ini/usbnicconfig.ini
ExecStart=/etc/init.d/dcismeng start
SERVICEEOF

    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to create $SYSTEMD_SERVICE_FILE"
        return 1
    fi

    systemctl daemon-reload > /dev/null 2>&1

    # Step 2: Divert the udev rules file so dpkg/dcism upgrades cannot restore it
    if ! dpkg-divert --list "$UDEV_RULE_FILE" | grep -q "$UDEV_RULE_FILE"; then
        dpkg-divert --local --rename --add "$UDEV_RULE_FILE" > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "ERROR: dpkg-divert failed for $UDEV_RULE_FILE"
            return 1
        fi
    fi

    # Step 3: Write the fixed non-blocking udev rule
    cat > "$UDEV_RULE_FILE" << 'RULEEOF'
# Dell USBNIC Device
# Modified for Debian/Proxmox systemd compatibility.
# Original ubuntu24 package uses blocking RUN+= which hangs udev-settle on Debian.
# Hands off to dcism-usbnic-hotplug.service via systemd instead.
SUBSYSTEM=="usb", ATTR{idVendor}=="413c", ATTR{idProduct}=="a102", ATTR{manufacturer}=="Dell(TM)", ACTION=="add", TAG+="systemd", ENV{SYSTEMD_WANTS}="dcism-usbnic-hotplug.service"
RULEEOF

    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to write fixed udev rule to $UDEV_RULE_FILE"
        return 1
    fi

    udevadm control --reload-rules > /dev/null 2>&1

    echo "udev boot fix applied successfully."
    echo "  - Installed: $SYSTEMD_SERVICE_FILE"
    echo "  - Diverted:  ${UDEV_RULE_FILE}.distrib (original preserved)"
    echo "  - Replaced:  $UDEV_RULE_FILE (non-blocking systemd handoff)"
    return 0
}

ApplyDebianUdevFix

exit $UPDATE_SUCCESS
 
