#!/bin/bash
>confirm_nats.log
while getopts "r:qhv" opt ; do
        case $opt in
                "q") QUIET=1 ;;
                "r") REMOTE_DB="$OPTARG" ; SQL_CMD="-h $REMOTE_DB -P7706" ;;
                "h") echo "$0 [-q] [-r {Primary DB IP}]"
                     echo "  where:"
                     echo "    -q = quiet mode, no output to screen"
                     echo "    -r {DB IP} = IP address of SL1 DB" ; echo ; exit 0 ;;
                "v") echo "$0, version 1.1" ; echo ; exit 0 ;;
        esac
done

IPS=( "$(silo_mysql -NBe "SELECT ip FROM master.system_settings_licenses WHERE function IN (5,6) AND ip LIKE '10.255.%'" $SQL_CMD)" )
for IP in ${IPS[@]} ; do
        CU_NAME="$(silo_mysql --ssl --connect-timeout=5 -h "$IP" -P 7707 -NBe "SELECT name FROM master.system_settings_licenses" 2> /dev/null)"
        DB_NAME="$(silo_mysql -NBe "SELECT name FROM master.system_settings_licenses WHERE ip='$IP'" $SQL_CMD 2> /dev/null)"
        NAT_PORTS=( $(grep "${IP}/" /etc/firewalld/direct_nat.xml | grep 7707 | awk -F":" {'print $2'} | awk -F"<" {'print $1'}) )
        [[ ! $NAT_PORTS[0] ]] && NAT_PORTS=( $(grep "${IP}/" /etc/firewalld/direct.xml 2> /dev/null | grep 7707 | awk -F":" {'print $2'} | awk -F"<" {'print $1'}) )
        for NAT_PORT in ${NAT_PORTS[@]} ; do
                NAT_NAME="$(silo_mysql --ssl --connect-timeout=5 -h 172.20.1.1 -P "$NAT_PORT" -NBe "SELECT name FROM master.system_settings_licenses" 2>/dev/null)" 
                if [ "$CU_NAME" != "$NAT_NAME" -o "$DB_NAME" != "$NAT_NAME" -o "$DB_NAME" != "$CU_NAME" ] ; then
                        echo "$IP: Failed: CU Name from CU DB: $CU_NAME CU Name from DB: $DB_NAME CU Name from NAT: $NAT_NAME" >> confirm_nats.log
                        [[ ! $QUIET ]] && echo "$IP: Failed: CU Name from CU DB: $CU_NAME CU Name from DB: $DB_NAME CU Name from NAT: $NAT_NAME" || echo -n "X"
                else
                        [[ ! $QUIET ]] && echo "$IP: Passed: $CU_NAME" || echo -n "."
                fi
        done
        unset NAT_PORTS
        sleep 2
done
echo
