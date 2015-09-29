#!/bin/sh

ps | grep sands/main.lua | grep -v grep >/dev/null 
test $? -eq 0 && exit 0

errorfile=/tmp/ugw/log/apmgr.error 

test -d /tmp/ugw/log/ || mkdir -p /tmp/ugw/log/ 
cd /ugw/apps/sands/

while :; do 
	lua53 /ugw/apps/sands/main.lua >/dev/null 2>>$errorfile
	sleep 2
done

