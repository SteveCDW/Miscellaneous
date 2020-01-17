#!/bin/bash
OUTFILE="$(hostname -s)-$(date +%Y%m%d).tgz"
PWD=$(grep ^dbpasswd /etc/silo.conf | head -1 | awk {'print $NF'})

log () {
	echo "[$(date +%F" "%T)] $1"
}

log "Starting config backup of $(hostname -s)"

for backup in "master" "master_access" "master_filestore" "master_biz" "master_custom" "master_dev" "master_dns" "master_reports" "scheduler" "mysql"; do 
        log "Backing up $backup"
        echo "use $backup;" > ${backup}.sql
        mysqldump -u root -p${PWD} -P7706 $backup >> ${backup}.sql
		CONFIG_FILES="$CONFIG_FILES ${backup}.sql"
done
echo "use master_events;" > master_events.sql
mysqldump -u root -p${PWD} -P7706 master_events event_suppressions >> master_events.sql
log "Backing up configuration files"
iptables-save > /tmp/iptables-backup
CONFIG_FILES="$CONFIG_FILES master_events.sql /tmp/iptables-backup"
for FILE in $(grep "^/" /etc/backup.conf) ; do
        if [ -e $FILE ] ; then
                CONFIG_FILES="$CONFIG_FILES $FILE"
        else
                log "Requested backup of $FILE, but it doesn't exist"
        fi
done
log "Creating $OUTFILE"
tar czf $OUTFILE $CONFIG_FILES /etc/my.cnf.d/silo_mysql.cnf /etc/drbd.d/r0.res /etc/firewalld/zones/drop.xml /etc/siteconfig
rm -f master*.sql scheduler.sql mysql.sql /tmp/iptables-backup
log "Done"
