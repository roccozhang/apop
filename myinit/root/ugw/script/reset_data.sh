#!/bin/sh
/etc/init.d/essential stop
killstr "essential/main.lua"
rm -rf /tmp/backup/*
sync 