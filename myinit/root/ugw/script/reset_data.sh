#!/bin/sh
/ugw/script/kdog.sh watchdog
/ugw/script/kdog.sh "essential/main.lua"
rm -rf /tmp/backup/*
sync 