#!/bin/sh

trap 'echo $( date ) $0 interrupted >&2; exit 2' INT TERM

until $@; do
 :
 sleep 10 
done
