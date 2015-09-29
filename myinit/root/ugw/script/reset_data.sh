#!/bin/sh 
/ugw/script/cfgmgr stop
/ugw/script/essential stop 
/ugw/script/logserver stop
/ugw/script/rds stop
/ugw/script/sands stop
/ugw/script/status stop
/ugw/script/tenacious stop
/ugw/script/userauth stop
/ugw/script/websrv stop
rm -rf /tmp/backup/*
sync 