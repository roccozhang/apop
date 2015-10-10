#!/bin/sh

ps | grep userauth/main.lua | grep -v grep >/dev/null 
test $? -eq 0 && exit 0

errorfile=/tmp/ugw/log/apmgr.error 

test -d /tmp/ugw/log/ || mkdir -p /tmp/ugw/log/ 
cd /ugw/apps/userauth/

while :; do 
	lsmod | grep auth_redirect >/dev/null 2>&1
	test $? -eq 0 && break 
	sleep 1 
done

while :; do 
	lua /ugw/apps/userauth/main.lua >/dev/null 2>>$errorfile
	sleep 2
done

