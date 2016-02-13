#!/bin/bash

. ./config

function cleanup {

rm -f /tmp/destination_snaps.$$ /tmp/source_snaps.$$

}

trap cleanup EXIT

REPLICA_POOL_BASE=${REPLICA_POOL%%/*}

set -e # exit if errors

lastSynced=$(ssh -A root@$REMOTEHOST  "zfs get -d 1 -H -t snapshot zfs-backup:synced $RPOOL/.rsync" |
 awk '($3 ~ "true") {print $0}' | tail -1 | cut -f 1 | cut -d '@' -f 2)

lastSnap=$(ssh -A root@$REMOTEHOST  "zfs list -d 1 -t snapshot -H $RPOOL/.rsync" | tail -1 | cut -f 1)

if [ -n "$lastSnap" ]; then

if [ ${lastSnap%%/.rsync@${lastSynced}} != $RPOOL ]; then


if [ -n "$lastSynced" ]; then
incrementalStart="-I @${lastSynced}"
fi
ssh -A root@$REMOTEHOST  "zfs send -R $incrementalStart $lastSnap |  \
mbuffer  -s 128k -m 1G 2>/dev/null | \
ssh -C ${REPLICA_HOST} \"mbuffer  -s 128k -m 1G 2>/dev/null | zfs receive -Fduv $REPLICA_POOL_BASE\""

ssh -A root@$REMOTEHOST  "zfs get zfs-backup:synced -d 1 -t snapshot -H $RPOOL/.rsync" | \
  awk '($3 !~ "true") {print $0}'| \
  cut -f 1  > /tmp/source_snaps.$$

ssh ${REPLICA_HOST} "zfs list -d 1 -t snapshot -H $REPLICA_POOL/.rsync" |  \
  cut -f 1 > /tmp/destination_snaps.$$

for snap in $(grep -f /tmp/destination_snaps.$$ /tmp/source_snaps.$$); do
echo "setting synced property to $snap"
ssh -A root@$REMOTEHOST "zfs set zfs-backup:synced=true ${snap}"
done

fi

fi
