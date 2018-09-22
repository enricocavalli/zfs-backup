#!/bin/sh

trap 'echo $( date ) $0 interrupted >&2; exit 2' INT TERM

while true
do
 $@
 sleep 3600 
done
