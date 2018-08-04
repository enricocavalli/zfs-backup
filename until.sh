#!/bin/sh

until $@; do
 :
 echo fail
 sleep 10 
done
