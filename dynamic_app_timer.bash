#!/bin/bash
while getopts "d:l:" opt ; do
        case $opt in
                "d") DID=$OPTARG ;;
                "l") LOGFILE="$OPTARG" ;;
        esac
done

log_it () {
        [[ $LOGFILE ]] && echo "[$(date +%F" "%T)] $1" >> $LOGFILE
        echo "$1"
}

[[ ! $DID ]] && echo "Must specify a device ID (-d {DID})" && echo && exit 1

APP_LIST=( $(silo_mysql -NBe "SELECT app_id FROM master.map_dynamic_app_device_cred WHERE did=$DID") )

log_it "Timing applications aligned to DID $DID"
for APP in ${APP_LIST[@]} ; do
        echo "Testing application $APP against device $DID"
        /usr/bin/time -p -o ${DID}_${APP}_output sudo -u s-em7-core /opt/em7/backend/dynamic_single.py $DID $APP > /dev/null 2> /dev/null
        ELAPSED_TIME="$(grep ^real ${DID}_${APP}_output | awk {'print $NF'})"
        log_it "  * App $APP completed in $ELAPSED_TIME seconds" 
        rm -f ${DID}_${APP}_output
        sleep 1
done
