#!/bin/bash
## REQUIRED VARIABLES
## Set these prior to implementation ##

API_USER="{PLEASE_DEFINE}"
DEV_ID={PLEASE_DEFINE}  # DID of stack device

#######################################
#
# Author: Steve Chapman [stevcha@cdw.com]
#
# New in:
#  1.0 [01/04/20] - initial release
#  1.1 [02/04/20] - Added log message if Daily Maintenance completes successfully
#                 - Added installation procedure
#  1.2 [03/04/20] - Changed Appliance ID finder to use hostname rather than IP
#                 - Fixed issue where installation script modified too many DEV_ID variables
#  1.3 [08/04/20] - Fixed typo in alert message
#  1.4 [10/04/20] - Enable logging levels
#                 - Fixed issue where script generated multiple API messages
#
VER="1.4"
LOG_LEVEL=0
LOCKFILE="/var/run/daily_maint_monitor.lock"
LOG_FILE="/root/daily_maint_monitor.log"
JSON_FILE="/root/daily_maint_monitor.json"
MFP="$(readlink -f "$0")"

help_msg() {
        echo ; echo "Usage: $MFP [-i] [-l] [-h] [-v]"
        echo "where: "
        echo "  -i = install"
        echo "  -l = enable logging to $LOG_FILE (logging levels from 1 to 3, based on the number of calls for this option (ie. \"-lll\" or \"-l -l -l\")"
        echo "  -h = help (what you're reading now)"
        echo "  -v = show version number (this is version ${VER}, just in case)"
        echo ; echo "Purpose:"
        echo "    This script runs from cron (/etc/crontab) every minute and monitors"
        echo "the progress of the Daily Maintenance process.  If it doesn't see that"
        echo "HAR RCA Data [pruner task 132] was the last completed task when the"
        echo "maint_daily pid disappeared, it generates an alert via the API"
        echo ; echo "Installation:"
        echo "  The installation process will prompt for the primary DB IP address if this is a secondary node."
        echo "  You will be asked to provide a device ID to which alerts should be sent, this is usually the cluster device."
        echo "  The device ID must be numeric, not the name."
        echo "  The job will be entered into cron with logging level 1. You can change it yourself, if necessary, but"
        echo "  there is no log rotation, so be wary."
        echo 
}

log_it() {
        (($LOG_LEVEL > 0 && $1 <= $LOG_LEVEL)) && echo "[$(date +"%Y-%m-%d %H:%M:%S")] $2" >> $LOG_FILE
}

validation() {
        MYSQL_CHECK=$(/opt/em7/bin/silo_mysql -NBe "SELECT 1" 2>/dev/null)
        [ ! $MYSQL_CHECK ] && log_it 2 "MySQL not running. Cancelling this session." && exit 0
}

perform_install() {
        MYSQL_CHECK=$(/opt/em7/bin/silo_mysql -NBe "SELECT 1" 2>/dev/null)
        if [ ! $MYSQL_CHECK ] ; then
                read -p "MySQL not running. If this is a secondary DB, please enter the IP address of the primary DB: " PRIMARY_IP
                [[ $PRIMARY_IP ]] && MYSQL_OPT="-h $PRIMARY_IP"
        fi
        [[ $(id -u) -ne 0 ]] && echo "Installation must be run as root" && echo && exit 1 
        chmod +x $MFP
        [[ $(grep ^API_USER $MFP | grep PLEASE_DEFINE | wc -l) -ne 1 || $(grep ^DEV_ID $MFP | grep PLEASE_DEFINE | wc -l) -ne 1 ]] && echo "Looks like this has already been installed. Please obtain a fresh copy of the base script and try again." && echo && exit 1
        [[ $(grep "${MFP}" /etc/crontab | wc -l) -gt 0 ]] && echo "Script already found in /etc/crontab. Remove before running installation again." && exit 1
        # GET MY ID
        log_it 1 "Beginning installation" && echo "Beginning installation"
        log_it 2 "Getting API account info"
        APP_ID=$(/opt/em7/bin/silo_mysql $MYSQL_OPT -NBe "SELECT id FROM master.system_settings_licenses WHERE name=\"$(hostname)\"")
        while [ ! $APP_ID ] ; do 
                read -p "Unable to determine Appliance ID. Please add it now: " APP_ID
                [[ $(/opt/em7/bin/silo_mysql $MYSQL_OPT -NBe "SELECT COUNT(id) FROM master.system_settings_licenses WHERE id=$APP_ID") -ne 1 ]] && unset APP_ID
        done
        API_USR_ID=$(/opt/em7/bin/silo_mysql $MYSQL_OPT -NBe "SELECT api_internal_account FROM master.system_settings_core")
        API_USR_ACCT="${API_USR_ID},${APP_ID},$(echo -n ${API_USR_ID}_SILO_API_INTERNAL_${APP_ID} | md5sum | awk {'print $1'})"
        # GET DID
        while [ ! $ALIGN_DID ] ; do
                read -p "To which device ID should alerts be posted: " ALIGN_DID
                [[ $ALIGN_DID ]] && [[ $(silo_mysql $MYSQL_OPT -NBe "SELECT COUNT(id) FROM master_dev.legend_device WHERE id=$ALIGN_DID") -ne 1 ]] && echo "DID not found. Try again." && unset ALIGN_DID
        done
        echo "Configuring alerts to be associated with DID $ALIGN_DID"
        sed -i "5s/API_USER=\"{PLEASE_DEFINE}\"/API_USER=\"${API_USR_ACCT}\"/" $MFP
        sed -i "6s/DEV_ID={PLEASE_DEFINE}/DEV_ID=$ALIGN_DID/" $MFP
        # Add to cron
        log_it 2 "Adding script to cron" && echo "Adding script to cron"
        echo "* * * * * root $MFP -l" >> /etc/crontab
        log_it 1 "Installation complete." && echo "Installation complete."
        exit 0
}

generate_api_alert() {
        log_it 1 "Generating API Alert: $API_MSG" 
        logger "EM7: Generating API Alert - $API_MSG"
        echo "{" > $JSON_FILE
        echo "  \"force_ytype\":\"0\"," >> $JSON_FILE
        echo "  \"force_yid\":\"0\"," >> $JSON_FILE
        echo "  \"force_yname\":\"\"," >> $JSON_FILE
        echo "  \"message\":\"${API_MSG}\"," >> $JSON_FILE
        echo "  \"message_time\":\"0\"," >> $JSON_FILE
        echo "  \"aligned_resource\":\"\/device\/$DEV_ID\"" >> $JSON_FILE
        echo "}" >> $JSON_FILE
        curl -sk -H "X-em7-beautify-reponse:1" -X POST -H "Content-Type: application/json" -d @${JSON_FILE} -u "${API_USER}:" https://localhost/api/alert > /dev/null 2>&1
        rm -f $JSON_FILE
}

while getopts "ilhv" opt ; do
        case $opt in
                "i") perform_install ;;
                "l") LOG_LEVEL=$((LOG_LEVEL+1)) ;;
                "h") help_msg ; exit 0 ;;
                "v") echo "$MFP, version $VER" ; echo ; exit 0 ;;
                *) echo "Invalid option" ; help_msg ; exit 1 ;;
        esac
done

validation
[[ "$API_USER" == "{PLEASE_DEFINE}" ]] && log_it 1 "Installation incomplete" && exit 1
if [[ -f "$LOCKFILE" ]] ; then
        log_it 2 "Already running" 
        exit 0
else
        touch $LOCKFILE
fi
PROC_PID=$(ps ax | grep maint_daily | grep python | awk {'print $1'})
if [ $PROC_PID ] ; then
         echo "$PROC_PID" > $LOCKFILE
else
        log_it 2 "Daily Maint not running" 
        rm -f $LOCKFILE
        exit 0
fi
log_it 2 "Found Daily Maintenance running on PID $PROC_PID"
while [ $PROC_PID -eq $(cat $LOCKFILE) ] ; do
        log_it 3 "Daily Maintenance is still running"
        sleep 30
        PROC_PID=$(ps ax | grep maint_daily | grep python | awk {'print $1'})
done
LAST_CHECK=$(/opt/em7/bin/silo_mysql -NBe "SELECT p_id FROM master_logs.pruner_log WHERE date_end != '' ORDER BY date_start DESC, p_id DESC LIMIT 1")
log_it 3 "Last Check: $LAST_CHECK"
if [ $LAST_CHECK -ne 132 ] ; then
        FAILED_TASK="$(/opt/em7/bin/silo_mysql -NBe "SELECT CONCAT(name,' [',ret_id,']') FROM master.system_settings_retention WHERE ret_id=$((LAST_CHECK+1))")"
        log_it 2 "Daily Maintenance process failed on task $FAILED_TASK"
        API_MSG="Daily Maintenance process failed on task $FAILED_TASK" 
else
        log_it 2 "Daily Maintenance completed successfully"
        API_MSG="Daily Maintenance completed successfully"
fi
generate_api_alert
rm -f $LOCKFILE
