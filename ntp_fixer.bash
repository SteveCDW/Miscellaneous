#!/bin/bash
VERSION="1.0"
NTP_CONF_FILE="/etc/chrony.d/servers.conf"
QUIET=0
LOG=0
RESTART=0

help_msg() {
        echo "$0, v.$VERSION"
        echo "Usage: $0 [-t {NTP/Time server IP}] [-l {log file name}] [-q] [-r] [-h] [-v]"
        echo "Where"
        echo "  -h = help message (what you're reading now)"
        echo "  -l {log file name} = file name to which to write log messages"
        echo "  -q = Quiet mode, suppresses output to screen"
        echo "  -r = restart chronyd service after fixing config file"
        echo "  -t = Time(NTP) server IP address. If not given, attempts to find the dbipaddrs entry from /etc/silo.conf"
        echo "  -v = show version number"
        echo "" 
}

logit () {
        [ $LOG -eq 1 ] && echo "[$(date +%F" "%T)] $1" >> $LOGFILE
        [ $QUIET -eq 0 ] && echo "[$(date +%F" "%T)] $1"
}

while getopts "HhL:l:QqRrT:t:Vv" opt ; do
        case $opt in
                "h"|"H") help_msg ; exit 0 ;;
                "l"|"L") LOG=1 ; LOGFILE="$OPTARG" ;;
                "q"|"Q") QUIET=1 ;;
                "r"|"R") RESTART=1 ;;
                "t"|"T") NTP_SERVER="$OPTARG" ;;
                "v"|"V") echo "$0, v.$VERSION" ; exit 0 ;;
                "*") echo "Invalid option" ; echo ; help_msg ; exit 1 ;;
        esac
done

if [ ! -f $NTP_CONF_FILE ] ; then
        QUIET=0
        logit "Unable to find $NTP_CONF_FILE"
        exit 1
fi
if [ "$NTP_SERVER" == "" ] ; then
        NTP_SERVER="$(grep ^dbip /etc/silo.conf | awk {'print $NF'})"
fi
if [ "$NTP_SERVER" == "" ] ; then
        QUIET=0
        logit "Unable to determine IP address to use for NTP server"
        exit 1
fi
logit "Backing up $NTP_CONF_FILE"
cp -p $NTP_CONF_FILE ${NTP_CONF_FILE}.pre-fix_$(date +%Y%m%d%H%M%S)
logit "NTP Server: $NTP_SERVER" 
logit "Inserting $NTP_SERVER to line 2 of $NTP_CONF_FILE"
sed "2 i server $NTP_SERVER iburst maxpoll 10" $NTP_CONF_FILE > $NTP_CONF_FILE.tmp
logit "Replacing bad OL time server entries with good RHEL entries"
sed 's/\.ol\./\.rhel\./g' $NTP_CONF_FILE.tmp > ${NTP_CONF_FILE}2.tmp
logit "Removing any duplicate lines"
awk '!seen[$0]++' ${NTP_CONF_FILE}2.tmp > $NTP_CONF_FILE
logit "Cleaning up temp files"
rm -f ${NTP_CONF_FILE}*.tmp
[[ $RESTART -eq 1 ]] && logit "Restarting chronyd" && systemctl restart chronyd
logit "Done"
