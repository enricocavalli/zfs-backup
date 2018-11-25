#!/bin/bash

INSTALLDIR=$( (cd -P $(dirname $0) && pwd) )
. "$INSTALLDIR/config-rsync"

LIMIT_PRUNE=${LIMIT_PRUNE:-0}
RPOOL=${MOUNT_POINT#/}



SOURCES="/"
if [ -f "$INSTALLDIR/sources.txt" ]; then
  SOURCES="--files-from=\"$INSTALLDIR/sources.txt\" -r /"
fi

EXCLUSIONS="--exclude-from=\"$INSTALLDIR/default-exclusions.txt\""
[ -f "$INSTALLDIR/exclusions.txt" ] && EXCLUSIONS="${EXCLUSIONS} --exclude-from=\"$INSTALLDIR/exclusions.txt\""

mkdir -p "$INSTALLDIR/logs"

global_return=0

eval nice -n 20 rsync \
-e \"'ssh -i $KEYFILEPATH'\" \
--log-file=\"$INSTALLDIR/logs/sync.log\" \
--fuzzy \
--sparse \
--delete \
--delete-excluded \
--recursive \
--group \
--owner \
--links \
--hard-links \
--times \
--devices \
--specials \
--verbose \
--perms \
--numeric-ids \
--compress \
--timeout=600 \
--itemize-changes \
--one-file-system \
$EXTRA_RSYNC_OPTIONS \
$EXCLUSIONS \
$SOURCES $REMOTE_USER@$REMOTEHOST:$MOUNT_POINT/

return=$?

if [ $return -eq 0 -o $return -eq 24 ]; then

  if [ ! -z "$PING_URL" ]; then
    curl -fsS --retry 3 "${PING_URL}" >/dev/null
  fi
  return=0
fi


exit $return
