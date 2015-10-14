#!/bin/sh

mkdir -p /tmp/www 
cd /www && cp -r webui /tmp/www/

ps | grep websrv/main.lua | grep -v grep >/dev/null 
test $? -eq 0 && exit 0

errorfile=/tmp/ugw/log/apmgr.error 

test -d /tmp/ugw/log/ || mkdir -p /tmp/ugw/log/ 
cd /ugw/apps/websrv/

while :; do 
	lua /ugw/apps/websrv/main.lua >/dev/null 2>>$errorfile
	sleep 2
done

