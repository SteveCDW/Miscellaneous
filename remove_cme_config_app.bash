#!/bin/bash
while getopts "u:p:l:" opt ; do
        case $opt in
                "u") USERNAME="$OPTARG" ;;
                "p") PASSWORD="$OPTARG" ;;
                "l") LOGFILE="$OPTARG" ; >$LOGFILE ;;
        esac
done

log_it () {
        [[ $LOGFILE ]] && echo "[$(date +%F" "%T)] $1" >> $LOGFILE
        echo "$1"
}

[[ ! $USERNAME ]] && echo "Username required" && exit 1
[[ ! $PASSWORD ]] && echo "Password required" && exit 1

app_id=$(silo_mysql -NBe "SELECT aid FROM master.dynamic_app WHERE name='Cisco CME: Configuration'")
[[ ! $app_id ]] && echo "Application not found" && exit 1
app_guid="$(silo_mysql -NBe "SELECT app_guid FROM master.dynamic_app WHERE name='Cisco CME: Configuration'")"
object_id=$(silo_mysql -NBe "SELECT obj_id FROM master.dynamic_app_objects WHERE app_id=$app_id AND name LIKE '%CCME Server%'")
ALIGNED_DEVICES=( $(silo_mysql -NBe "SELECT did FROM master.map_dynamic_app_device_cred WHERE app_id=$app_id") )

[[ ${#ALIGNED_DEVICES[@]} -eq 0 ]] && log_it "No devices aligned to specified app" && exit 0 || log_it "Found ${#ALIGNED_DEVICES[@]} devices aligned to specified app"

for DID in ${ALIGNED_DEVICES[@]} ; do
        log_it "Checking $DID"
        VALUE=$(silo_mysql -NBe "SELECT data FROM dynamic_app_data_${app_id}.dev_config_${DID} WHERE object=${object_id} ORDER BY collection_time DESC LIMIT 1" 2>/dev/null)
        [[ ! $VALUE ]] && log_it "DID ${DID}: No data found. Skipping."
        [[ $VALUE -eq 1 ]] && log_it "DID ${DID}: Properly aligned. "
        [[ $VALUE -eq 2 ]] && curl -k -u "${USERNAME}:${PASSWORD}" -X DELETE https://localhost/api/device/${DID}/aligned_app/${app_guid} && log_it "DID ${DID}: Removed"
done
