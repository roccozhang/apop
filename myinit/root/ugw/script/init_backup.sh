#!/bin/sh
BACKUP_DIR=/tmp/backup
BACKUP_PART=7
LOG_DIR=/ugw/log
LOGFILE=$LOG_DIR/init_backup.log
mkdir -p $LOG_DIR
log() {
	echo `date` $* >> $LOGFILE
	echo $*
}

mount_backup() {
	test -d $BACKUP_DIR || mkdir -p $BACKUP_DIR
	mount -t jffs2 /dev/mtdblock${BACKUP_PART} $BACKUP_DIR
	if [ $? -ne 0 ]; then 
		log "mount $BACKUP_DIR fail, re-format" 
	else 
		test -d $BACKUP_DIR/root && return
		log "mount $BACKUP_DIR ok but not find $BACKUP_DIR/root, re-format"
		umount $BACKUP_DIR || log "unmount $BACKUP_DIR fail"
	fi

	umount $BACKUP_DIR >/dev/null 2>&1

	mtd erase "conf-backup"
	test $? -eq 0 || log "mtd erase fail"

	mount -t jffs2 /dev/mtdblock${BACKUP_PART} $BACKUP_DIR
	if [ $? -ne 0 ]; then 
		log "mount $BACKUP_DIR fail, ERROR" 
		return
	fi

	mount | grep mtdblock${BACKUP_PART} | grep backup >/dev/null 2>&1
	if [ $? -ne 0 ]; then 
		log "format and mount fail" 
		sleep 5
		reboot 
		exit 1
	fi

	log "format and mount ok" 
	mkdir -p $BACKUP_DIR/root
	if [ $? -ne 0 ]; then 
		log "mkdir $BACKUP_DIR/root fail. reboot"
		sleep 5
		reboot
	fi 
}

mount | grep mtdblock${BACKUP_PART} | grep backup >/dev/null 2>&1
if [ $? -eq 0 ]; then 
	test -d $BACKUP_DIR/root && exit 0
fi

mount_backup