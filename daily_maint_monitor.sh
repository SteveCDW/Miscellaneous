#!/bin/bash
#
# Author: Steve Chapman [stevcha@cdw.com]
#
# New in:
#  1.0 [01/04/20] - initial release
#  1.1 [02/04/20] - Added log message if Daily Maintenance completes successfully
#                 - Added installation procedure
#
VER="1.1"
LOCKFILE="/var/run/daily_maint_monitor.lock"
LOG_FILE="/root/daily_maint_monitor.log"
JSON_FILE="/root/daily_maint_monitor.json"
PROC_PID=$(ps ax | grep maint_daily | grep -v grep | awk {'print $1'} | tail -1)

## REQUIRED VARIABLES
## Set these prior to implementation ##

API_USER="{PLEASE_DEFINE}"
DEV_ID={PLEASE_DEFINE}  # DID of stack device

#######################################

help_msg() {
        echo ; echo "Usage: $(readlink -f "$0") [-i] [-l] [-h] [-v]"
        echo "where: "
        echo "  -i = install"
        echo "  -l = enable logging to $LOG_FILE"
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
        echo "  The job will be entered into cron without the logging option. You can add it yourself, if necessary, but"
        echo "  there is no log rotation and this will make at least one entry per minute, so be wary."
        echo 
}

log_it() {
        [[ $ENABLE_LOGGING ]] && echo "[$(date +"%Y-%m-%d %H:%M:%S")] $1" >> $LOG_FILE
}

validation () {
        MYSQL_CHECK=$(/opt/em7/bin/silo_mysql -NBe "SELECT 1" 2>/dev/null)
        [ ! $MYSQL_CHECK ] && log_it "MySQL not running. Cancelling this session." && exit 0
}

perform_install () {
        MYSQL_CHECK=$(/opt/em7/bin/silo_mysql -NBe "SELECT 1" 2>/dev/null)
        if [ ! $MYSQL_CHECK ] ; then
                read -p "MySQL not running. If this is a secondary DB, please enter the IP address of the primary DB: " PRIMARY_IP
                [[ $PRIMARY_IP ]] && MYSQL_OPT="-h $PRIMARY_IP"
        fi
        [[ $(id -u) -ne 0 ]] && echo "Installation must be run as root" && echo && exit 1 
        chmod +x $(readlink -f "$0")
        [[ $(grep ^API_USER $0 | grep PLEASE_DEFINE | wc -l) -ne 1 || $(grep ^DEV_ID $0 | grep PLEASE_DEFINE | wc -l) -ne 1 ]] && echo "Looks like this has already been installed. Please obtain a fresh copy of the base script and try again." && echo && exit 1
        [[ $(grep "$(readlink -f "$0")" /etc/crontab | wc -l) -gt 0 ]] && echo "Script already found in /etc/crontab. Remove before running installation again." && exit 1
        # GET MY ID
        echo "Beginning installation"
        log_it "Getting API account info"
        APP_IP="$(ip addr |grep inet |grep -v inet6 |grep -v "host lo" |awk {'print $2'} |awk -F"/" {'print $1'})"
        APP_ID=$(/opt/em7/bin/silo_mysql $MYSQL_OPT -NBe "SELECT id FROM master.system_settings_licenses WHERE ip=\"$APP_IP\"")
        API_USR_ID=$(/opt/em7/bin/silo_mysql $MYSQL_OPT -NBe "SELECT api_internal_account FROM master.system_settings_core")
        API_USR_ACCT="${API_USR_ID},${APP_ID},$(echo -n ${API_USR_ID}_SILO_API_INTERNAL_${APP_ID} | md5sum | awk {'print $1'}):"
        sed -i "s/API_USER=\"{PLEASE_DEFINE}\"/API_USER=\"${API_USR_ACCT}\"/" $0
        # GET DID
        while [ ! $ALIGN_DID ] ; do
                read -p "To which device ID should alerts be posted: " ALIGN_DID
                [[ $ALIGN_DID ]] && [[ $(silo_mysql $MYSQL_OPT -NBe "SELECT COUNT(id) FROM master_dev.legend_device WHERE id=$ALIGN_DID") -ne 1 ]] && echo "DID not found. Try again." && unset ALIGN_DID
        done
        echo "Configuring alerts to be associated with DID $ALIGN_DID"
        sed -i "s/API_USER=\"{PLEASE_DEFINE}\"/API_USER=\"${API_USR_ACCT}\"/" $0
        sed -i "s/DEV_ID={PLEASE_DEFINE}/DEV_ID=$ALIGN_DID/" $0
        # Add to cron
        echo "Adding script to cron"
        echo "* * * * * root $(readlink -f "$0")" >> /etc/crontab
        echo "Installation complete."
        exit 0

}

validation () {
        MYSQL_CHECK=$(/opt/em7/bin/silo_mysql -NBe "SELECT 1" 2>/dev/null)
        [ ! $MYSQL_CHECK ] && log_it "MySQL not running. Cancelling this session." && exit 0
}

generate_api_alert() {
        log_it "Generating API Alert" 
        LAST_CHECK=58
        FAILED_TASK="$(/opt/em7/bin/silo_mysql -NBe "SELECT CONCAT(name,' [',ret_id,']') FROM master.system_settings_retention ret_id=$((LAST_CHECK+1))")"
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
                "l") ENABLE_LOGGING=1 ;;
                "h") help_msg ; exit 0 ;;
                "v") echo "$0, version $VER" ; echo ; exit 0 ;;
                *) echo "Invalid option" ; help_msg ; exit 1 ;;
        esac
done

validation
[[ "$API_USER" == "{PLEASE_DEFINE}" ]] && log_it "Installation incomplete" && exit 1
[[ -f $LOCKFILE ]] && log_it "Already running" && exit 0
[[ $PROC_PID ]] && echo "$PROC_PID" > $LOCKFILE || log_it "Daily Maint not running"
if [ -f $LOCKFILE ] ; then
        log_it "Found Daily Maintenance running on PID $PROC_PID"
        while [ $(ps ax | grep maint_daily | grep -v grep | awk {'print $1'}| tail -1) -eq $PROC_PID ] ; do
                sleep 30
        done
        LAST_CHECK=$(/opt/em7/bin/silo_mysql -NBe "SELECT p_id FROM master_logs.pruner_log WHERE date_end != '' ORDER BY date_start DESC, p_id DESC LIMIT 1")
        log_it "Last Check: $LAST_CHECK"
        if [ $LAST_CHECK -ne 132 ] ; then
                 FAILED_TASK="$(/opt/em7/bin/silo_mysql -NBe "SELECT CONCAT(name,' [',ret_id,']') FROM master.system_settings_retention ret_id=$((LAST_CHECK+1))")"
                 API_MSG="Daily Maintenance process failed on task $FAILED_TASK" 
        else
                log_it "Daily Maintenance completed successfully"
                API_MSG="Daily Maintenance completed successfully"
        fi
        generate_api_alert
        rm -f $LOCKFILE
fi
