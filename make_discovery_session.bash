#!/bin/bash
#
# Version History:
# 1.1 - created variables for API credentials
# 1.0 - Initial Release
#
VER="1.1"
DISCOVER_NON_SNMP=0
OUTFILE="discovery_session.json"
API_SERVER="localhost"

help_msg () {
        echo ; echo "Usage: $0 --ip={IP address} --org=\"{organization}\" --collector={name of collector} --api-user={username} --api-password={password} [--db-ip={IP Address of DB appliance}] [--job-name=\"{name}\"] [--skip-snmp] [--snmp_cred=\"{snmp credential ID}\"] [--ps-cred=\"{PS Cred ID}\"] [--add-port={port number}] [--ignore-dupes] [--template=\"{device template}\"] [--dev-group=\"{device group}\"] [-o {file name}] [--pre-flight] [--run-now ] [-h] [-v]"
        echo ; echo "where:"
        echo "  --ip = ip address to discover, required field"
        echo "  --org = organization to which this device will be added, required field"
        echo "  --collector = name of collector that will be performing the discovery, required field"
        echo "  --db-ip = IP Address of DB appliance or API (default: localhost)"
        echo "  --api-user= User name with which to access the API, required field"
        echo "  --api-password= Password to use to access the API, required field"
        echo "  --job-name = name of the discovery job"
        echo "  --skip-snmp = do not attempt to use SNMP in discovery"
        echo "  --snmp-cred = SNMP credential ID to use in discovery session*"
        echo "  --ps-cred = Powershell credential ID to use in discovery session*"
        echo "  --add-port = additional network port to check aside from the default (21,22,23,25,80)"
        echo "  --ignore-dupes = do not apply duplication protection"
        echo "  --template = Device Template to apply during discovery"
        echo "  --dev-group = Device Group to which to add the device"
        echo "  --pre-flight = perform pre-flight checks"
        echo "  --run-now = run discovery session after creating it"
        echo "  -o = file to which to write the discovery session JSON package (default: $OUTFILE)"
        echo "  -h = help message (what you're reading now)"
        echo "  -v = show version"
        echo ; echo "* either an SNMP credential or a powershell credential (or both) is required"
        echo
}

hit_api () {
        #curl -vsk -X $1 -H 'X-em7-beautify-response:1' -u "${API_CRED}" "https://$API_SERVER/api/$2"
        curl -sk -X $1 -u "${API_CRED}" "https://$API_SERVER/api/$2"
}

get_org () {
        ORG_WEB_NAME="${ORG// /%20}"
        ORG_ID=$(hit_api GET "organization?limit=1&hide.filterinfo=1&filter.0.company.eq=$ORG_WEB_NAME" | grep URI | awk -F"/" {'print $NF'}| awk -F"\"" {'print $1'})
        [[ ! $ORG_ID ]] && echo "Unable to find a record for organization \"$ORG\"" && unset ORG || ORG="/api/organization/$ORG_ID"
}

get_collector () {
        COLLECTOR_ID=$(hit_api GET "appliance?limit=1&hide.filterinfo=1&filter.0.name.eq=$COLLECTOR" | grep URI | awk -F"/" {'print $NF'}| awk -F"\"" {'print $1'})
        [[ ! $COLLECTOR_ID ]] && echo "Unable to find collector $COLLECTOR" && unset COLLECTOR || COLLECTOR="/api/appliance/$COLLECTOR_ID"
        [[ $COLLECTOR ]] && COLLECTOR_IP=$(hit_api GET "appliance/$COLLECTOR_ID" | python -c "import sys, json; print json.load(sys.stdin)['ip']")
}

get_cred_guid () {
        CRED_GUID=$(hit_api GET "credential/${CRED_TYPE}?limit=1&hide.filterinfo=1&filter.0.cred_name.eq=$CRED_WEB_NAME" | grep URI | awk -F"/" {'print $NF'}| awk -F"\"" {'print $1'})

}

check_cred_on_collector () {
        if [ $(/opt/em7/bin/silo_mysql -h $COLLECTOR_IP -P7707 -NBe "SELECT COUNT(*) FROM master.system_credentials WHERE cred_name='${CRED_NAME}'") -eq 1 ] ; then
                echo "[Pre-Flight] $CRED_NAME found on target collector"
        else
                echo "[Pre-Flight] $CRED_NAME does not exist on the target collector"
                PF_FAIL=1
        fi
}

check_host_file_on_collector () {
        if [ $PF ] ; then
                module-cmd $COLLECTOR_ID "grep $IP_ADDR /etc/hosts" > /dev/null 2>&1
                [[ $? -eq 1 ]] && echo "[Pre-Flight] $IP_ADDR not found in target collector's /etc/hosts file" && PF_FAIL=1
        fi

}
get_cred () {
        CRED_TYPE="$1"
        case $CRED_TYPE in
                "snmp") CRED_WEB_NAME="${SNMP_CRED// /%20}"
                        CRED_NAME="$SNMP_CRED" ;;
                "powershell") CRED_WEB_NAME="${PS_CRED// /%20}"
                              CRED_NAME="$PS_CRED" ;;
        esac
        get_cred_guid
        if [ ! $CRED_GUID ] ; then
                echo "Unable to find $CRED_TYPE credential \"$PS_CRED\"" 
                case $CRED_TYPE in 
                        "snmp") unset SNMP_CRED ;;
                        "powershell") unset PS_CRED ;;
                esac
        else
                case $CRED_TYPE in
                        "snmp") SNMP_CRED="/api/credential/snmp/$CRED_GUID" ;;
                        "powershell") PS_CRED="/api/credential/powershell/$CRED_GUID" ;;
                esac
                [[ $PF ]] && check_cred_on_collector
        fi
        unset CRED_GUID CRED_NAME CRED_WEB_NAME CRED_TYPE
}

get_dev_template () {
        TEMPLATE_WEB_NAME="${DEV_TEMPLATE// /%20}"
        DEV_TEMPLATE_ID=$(hit_api GET "device_template?limit=1&hide.filterinfo=1&filter.0.template_name.eq=$TEMPLATE_WEB_NAME" | grep URI | awk -F"/" {'print $NF'}| awk -F"\"" {'print $1'})
        [[ ! $DEV_TEMPLATE_ID ]] && echo "Unable to find device template \"${DEV_TEMPLATE}\", proceeding without assigning a template" && unset DEV_TEMPLATE || DEV_TEMPLATE="/api/device_template/$DEV_TEMPLATE_ID"
}

validate_addl_port () {
        case $ADDL_PORT in
                21 | 22 | 23 | 25 | 80) echo "Ignoring attempt to add a default port" ; unset ADDL_PORT ;;
                161) printf "Please specify [U]DP or [T]CP? "
                     read UORT
                     case $UORT in
                        "U" | "u" | "UDP" | "udp") ADDL_PORT="SNMP" 
                     esac ;;
        esac
}

while getopts "u:p:hv-:" opt ; do
        case $opt in
                "o") OUTFILE="$OPTARG" ;;
                "u") API_USER="$OPTARG" ;;
                "p") API_PASS="$OPTARG" ;;
                "h") help_msg ; exit 0 ;;
                "v") echo ; echo "$0, version $VER" ; echo ; exit 0 ;;
                "-") case "$OPTARG" in
                        ip=*) IP_ADDR="$(echo $OPTARG | cut -f 1 -d '=' --complement)" ;;
                        snmp-cred=*) SNMP_CRED="$(echo $OPTARG | cut -f 1 -d '=' --complement)" ;;
                        ps-cred=*) PS_CRED="$(echo $OPTARG | cut -f 1 -d '=' --complement)" ; DISCOVER_WIN=1 ;;
                        db-ip=* | api-ip=*) API_SERVER="$(echo $OPTARG | cut -f 1 -d '=' --complement)" ;;
                        db-user=* | api-user=*) API_USER="$(echo $OPTARG | cut -f 1 -d '=' --complement)" ;;
                        db-password=* | api-password=*) API_PASS="$(echo $OPTARG | cut -f 1 -d '=' --complement)" ;;
                        collector=*) COLLECTOR="$(echo $OPTARG | cut -f 1 -d '=' --complement)" ;;
                        org=* | organization=*) ORG="$(echo $OPTARG | cut -f 1 -d '=' --complement)" ;;
                        job-name=*) JOB_NAME="$(echo $OPTARG | cut -f 1 -d '=' --complement)" ;;
                        ignore-dupes) IGNORE_DUPES=1 ;;
                        dev-group=*) DEV_GROUP="$(echo $OPTARG | cut -f 1 -d '=' --complement)" ;;
                        skip-snmp | no-snmp) DISCOVER_NON_SNMP=1 ;;
                        template=*) DEV_TEMPLATE="$(echo $OPTARG | cut -f 1 -d '=' --complement)" ;;
                        add-port=*) ADDL_PORT="$(echo $OPTARG | cut -f 1 -d '=' --complement)" ;;
                        pre-flight) PF=1 ;;
                        run-now) RUN_NOW=1 ;;
                     esac ;;
                *) echo ; echo "Invalid option" ; help_msg ; exit 1 ;;
        esac
done

[[ ! $API_USER || ! $API_PASS ]] && echo "No API credentials provided." && echo && exit 1
API_CRED="${API_USER}:${API_PASS}"
if [ $PF ] ; then
        [[ "$(whoami)" != "root" ]] && echo "Pre-flight check requires root access" && exit 1
fi

get_org
get_collector
[[ ! $IP_ADDR || ! $COLLECTOR || ! $ORG ]] && echo "Required parameter missing" && exit 1
[[ ! $SNMP_CRED ]] && echo "No SNMP credential provided, adding \"Discover non-SNMP\" to job" && DISCOVER_NON_SNMP=1 || get_cred snmp
[[ $PS_CRED ]] && get_cred powershell && check_host_file_on_collector
[[ ! $SNMP_CRED && ! $PS_CRED ]] && echo "No valid credential found" && exit 1
[[ $ADDL_PORT ]] && validate addl_port 
[[ $DEV_TEMPLATE ]] && get_dev_template

echo "{" > $OUTFILE
echo "  \"organization\": \"${ORG}\"," >> $OUTFILE
echo "  \"aligned_collector\": \"${COLLECTOR}\"," >> $OUTFILE
[[ $DEV_TEMPLATE ]] && echo "  \"aligned_device_template\": \"${DEV_TEMPLATE}\"," >> $OUTFILE
echo "  \"discover_non_snmp\": \"${DISCOVER_NON_SNMP}\"," >> $OUTFILE
if [ $ADDL_PORT ] ; then
        echo "  \"scan_ports\": [" >> $OUTFILE
        echo "    \"21\"," >> $OUTFILE
        echo "    \"22\"," >> $OUTFILE
        echo "    \"23\"," >> $OUTFILE
        echo "    \"25\"," >> $OUTFILE
        echo "    \"80\"," >> $OUTFILE
        echo "    \"${ADDL_PORT}\"" >> $OUTFILE
        echo "  ]," >> $OUTFILE
fi
[[ $IGNORE_DUPES ]] && echo "  \"duplicate_protection\": \"0\"," >> $OUTFILE
[[ $JOB_NAME ]] && echo "  \"name\": \"${JOB_NAME}\"," >> $OUTFILE
echo "  \"ip_lists\": [" >> $OUTFILE
echo "     {" >> $OUTFILE
echo "       \"start_ip\": \"${IP_ADDR}\"," >> $OUTFILE
echo "       \"end_ip\": \"${IP_ADDR}\"" >> $OUTFILE
echo "     }" >> $OUTFILE
echo "  ]," >> $OUTFILE
echo "  \"credentials\": [" >> $OUTFILE
if [ $SNMP_CRED ] ; then
         [[ $PS_CRED ]] && echo "    \"$SNMP_CRED\"," >> $OUTFILE || echo "    \"$SNMP_CRED\"" >> $OUTFILE
fi
[[ $PS_CRED ]] && echo "    \"$PS_CRED\"" >> $OUTFILE
echo "  ]" >> $OUTFILE
echo "}" >> $OUTFILE

if [ $PF_FAIL ] ; then
        printf "Pre-flight check failed. Are you sure you want to continue? [y|N] "
        read YORN
        case $YORN in
                "Y"|"y"|"Yes"|"yes"|"YES") curl -sk -X POST -H 'Content-Type: application/json' -d @${OUTFILE} -u "${API_CRED}" "https://API_SERVER/api/discovery_session_active" ;;
                *) echo "Discovery session not created by user choice" && echo && rm -f $OUTFILE && exit 0 ;;
        esac
fi

if [ $RUN_NOW ] ; then
        curl -sk -X POST -H 'Content-Type: application/json' -d @${OUTFILE} -u "${API_CRED}" "https://API_SERVER/api/discovery_session_active" 
else
        RESPONSE=$(curl -sk -X POST -H 'Content-Type: application/json' -d @${OUTFILE} -u "${API_CRED}" "https://$API_SERVER/api/discovery_session")
        DISCOVERY_SESSION_ID=$(echo $RESPONSE | awk -F "discovery_session" {'print $2'} | awk -F"/" {'print $2'} | awk -F"\\" {'print $1'})
        echo "Created discovery session $DISCOVERY_SESSION_ID"
fi
rm -f $OUTFILE