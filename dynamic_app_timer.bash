#!/bin/bash
#
VER="1.0"

help_msg () {
    echo ; echo "Usage: $0 -d {device ID} [-a {app ID}] [-h] [-v]"
    echo ; echo "where:"
    echo "  -d (--did={device ID}) = device ID, required"
    echo "  -a (--aid={app ID}) = dynamic app ID, optional. If not set, will time all applications aligned to the device. If timing more than one, use \"-a {app ID}\" for each."
    echo "  -h (--help) = help message (what you're reading now)"
    echo "  -v (--version) = show version and exit"
    echo
}

while getopts "d:a:hv-:" opt ; do
    case $opt in
        "d") DID=$OPTARG ;;
        "a") APPS+=( $OPTARG ) ;;
        "h") help_msg ; exit 0 ;;
        "v") echo ; echo "$0, version $VER" ; echo ; exit 0 ;;
        -) case $OPTARG in
              did=* | device=*) DID="$(echo $OPTARG | cut -f 1 -d '=' --complement)" ;;
              aid=* | app_id=* | app-id=* | app=* | da=* | dynamic_app=* | dynamic-app=*) APPS+=( "$(echo $OPTARG | cut -f 1 -d '=' --complement)" ) ;;
              help) help_msg ; exit 0 ;;
              version) echo ; echo "$0, version $VER" ; echo ; exit 0 ;;
           esac ;;
        *) echo "Invalid option" ; exit 1 ;;
    esac
done

[[ ! $DID ]] && echo "DID required" && exit 1
[[ ! $APPS ]] && APPS=( $(silo_mysql -NBe "SELECT app_id FROM master.map_dynamic_app_device_cred WHERE did=$DID") )

echo "Testing ${#APPS[@]} apps on DID $DID:"
for APP in ${APPS[@]} ; do
    echo -n "  * Seconds to complete App ID $APP: "
    SECONDS=0
    sudo -u s-em7-core /opt/em7/backend/dynamic_single.py $DID $APP >/dev/null 2>&1
    echo $SECONDS
done
