#!/bin/sh

. ./config


if [ -n "$1" ] && [ "$1" = "close" ] 
then
  $SSH root@$REMOTEHOST "zpool export ${RPOOL%%/*}"

  for device in $DEVICES_REMOTEHOST; do
    device_name_sha=$(/bin/echo -n "${device}${REMOTEHOST}" | shasum | cut -d ' ' -f 1)
    device_name="zfs-${device_name_sha:0:8}"
    $SSH root@$REMOTEHOST "cryptsetup luksClose ${device_name}"
  done


  if [ -n "$REPLICA_HOST" ]; then
  $SSH root@$REPLICA_HOST "zpool export ${RPOOL%%/*}"
  for device in $DEVICES_REPLICAHOST; do
    device_name_sha=$(/bin/echo -n "${device}${REPLICA_HOST}" | shasum | cut -d ' ' -f 1)
    device_name="zfs-${device_name_sha:0:8}"
    $SSH root@$REPLICA_HOST "cryptsetup luksClose ${device_name}"
  done

  fi
  echo "tutto chiuso"
  exit
fi

if ! $SSH root@$REMOTEHOST "[ -d /$RPOOL/.rsync ]"
  then
    set -e
    read -s -p "Enter passphrase to decrypt devices: " pf
    echo # simulate new line
    /bin/echo -n "Opening devices: "
    # echo builtin does not have -n option
    for device in $DEVICES_REMOTEHOST; do
      device_name_sha=$(/bin/echo -n "${device}${REMOTEHOST}" | shasum | cut -d ' ' -f 1)
      device_name="zfs-${device_name_sha:0:8}"
      /bin/echo -n "${pf}" | $SSH root@$REMOTEHOST "cryptsetup luksOpen --key-file=- ${device} ${device_name}"
    done
    
    $SSH root@$REMOTEHOST "zpool import ${RPOOL%%/*}"

    if [ -n "$REPLICA_HOST" ]; then
    for device in $DEVICES_REPLICAHOST; do
      device_name_sha=$(/bin/echo -n "${device}${REPLICA_HOST}" | shasum | cut -d ' ' -f 1)
      device_name="zfs-${device_name_sha:0:8}"
      /bin/echo -n "${pf}" | $SSH root@$REPLICA_HOST "cryptsetup luksOpen --key-file=- ${device} ${device_name}"
    done
    $SSH root@$REPLICA_HOST "zpool import ${RPOOL%%/*}"
    fi
    echo "done."
    set +e 
  fi
