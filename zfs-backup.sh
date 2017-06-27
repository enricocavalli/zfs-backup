#!/bin/bash

INSTALLDIR=$( (cd -P $(dirname $0) && pwd) )
. "$INSTALLDIR/config"

function date_calc {

year=$1
month=$2
day=$3
hour=$4
min=$5
sec=$6

format=$7

if uname -a | grep -q Darwin; then
  # OS X date
  date -j -f "%Y %m %d %H %M %S" "$year $month $day $hour $min $sec" "$format"
else
  # GNU date
  date -d "$year-$month-$day $hour:$min:$sec" "$format"
fi

}


mkdir -p "$INSTALLDIR/logs"
MOUNT_POINT="/mnt/$RPOOL"

if ! ssh $REMOTE_USER@$REMOTEHOST "[ -d $MOUNT_POINT ]"
  then
  echo "Remote filesystem not mounted"
  exit 1
fi

SOURCES="/"
if [ -f "sources.txt" ]; then
  SOURCES="--files-from=\"$INSTALLDIR/sources.txt\" -r /"
fi

EXCLUSIONS="--exclude-from=\"$INSTALLDIR/default-exclusions.txt\""
[ -f "./exclusions.txt" ] && EXCLUSIONS="${EXCLUSIONS} --exclude-from=\"$INSTALLDIR/exclusions.txt\""

echo "Checking sudo execution"
sudo true || exit 1

now="$(date +%Y-%m-%d-%H%M%S)"

echo "##### BEGIN RSYNC"
eval sudo nice -n 20 rsync \
-e \"'ssh -i $KEYFILEPATH'\" \
--log-file=\"$INSTALLDIR/logs/sync.log\" \
--fuzzy \
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
--partial \
--progress \
--timeout=600 \
--itemize-changes \
--one-file-system \
$EXTRA_RSYNC_OPTIONS \
$EXCLUSIONS \
$SOURCES $REMOTE_USER@$REMOTEHOST:$MOUNT_POINT/

return=$?
echo "##### END RSYNC"

if [ $return -eq 0 -o $return -eq 24 ]; then
  echo "##### begin snapshot"
  ssh $REMOTE_USER@$REMOTEHOST "zfs snapshot -r $RPOOL@$now && zfs clone $RPOOL@$now ${RPOOL}_$now"

  echo "##### BEGIN AUTOPRUNE"

  # determine the last synced snapshot
  lastSEND=$(ssh $REMOTE_USER@$REMOTEHOST "zfs get -d 1 -H -t snapshot zfs-backup:synced $RPOOL" | awk '($3 ~ "true") {print $0}' | tail -1 | cut -f 1 | cut -d '@' -f 2 | grep -v ^auto-)

  if [ -n "$lastSEND" ] ; then
  sec="${lastSEND:15:2}"
  min="${lastSEND:13:2}"
  hour="${lastSEND:11:2}"
  day="${lastSEND:8:2}"
  mon="${lastSEND:5:2}"
  year="${lastSEND:0:4}"

  sendEpoc=`date_calc $year $mon $day $hour $min $sec "+%s"`
  fi
  curEpoc=`date +%s`
  lastYear=""; lastMon=""; lastDay=""; lastHour="" lastMin="" ; lastSec=""
  # Get our list of snaps
  snaps=$(ssh $REMOTE_USER@$REMOTEHOST "zfs list -d 1 -t snapshot -H $RPOOL" | cut -f 1 | cut -d '@' -f 2 | grep -v ^auto-)

  # Reverse the list, sort from newest to oldest
  for tmp in $snaps
  do
     rSnaps="$tmp $rSnaps"
  done

  num=0
  for snap in $rSnaps
  do
     # date format assumed: YYYY-mm-dd-HHMMSS"
     sec="${snap:15:2}"
     min="${snap:13:2}"
     hour="${snap:11:2}"
     day="${snap:8:2}"
     mon="${snap:5:2}"
     year="${snap:0:4}"

     # Convert this snap to epoc time
     snapEpoc=`date_calc $year $mon $day $hour $min $sec "+%s"`
     week=`date_calc $year $mon $day $hour $min $sec "+%G%V"`


   # If we are replicating, don't prune anything which hasn't gone out yet
     if [ -n "$sendEpoc" ] ; then
        if [ $sendEpoc -lt $snapEpoc ] ; then
          echo "$snap not synced: excluding from auto prune"
          continue;
          fi
     fi

     # Get the epoch time elapsed
     check=`expr $curEpoc - $snapEpoc`
     pruned=0

     # Looking for snaps older than 12 months
     #if [ $check -gt 31536000 ]; then
     #   echo "Destroy $snap"
     #   ssh $REMOTE_USER@$REMOTEHOST "zfs destroy -r  data@$snap"
     #   pruned=1
     #fi

     # Looking for multiple snaps older than 30 days
     if [ $check -gt 2592000 -a $pruned -eq 0 ]; then
        # Did we already have a snapshot from this week?
        if [ "$week" = "$lastWeek" ] ; then
          echo "Destroy $snap"
          ssh $REMOTE_USER@$REMOTEHOST "zfs destroy -r -R $RPOOL@$snap"
          pruned=1
        fi
     fi

     # Looking for multiple snaps older than a day
     if [ $check -gt 86400 -a $pruned -eq 0 ]; then
        if [ "$week" = "$lastWeek" -a "$day" = "$lastDay" ] ; then
          echo "Destroy $snap"
          ssh $REMOTE_USER@$REMOTEHOST "zfs destroy -r -R $RPOOL@$snap"
          pruned=1
        fi
     fi

     # Looking for multiple snaps older than an hour
     if [ $check -gt 3600 -a $pruned -eq 0 ]; then
        if [ "$week" = "$lastWeek" -a "$day" = "$lastDay" -a "$hour" = "$lastHour" ] ; then
          echo "Destroy $snap"
          ssh $REMOTE_USER@$REMOTEHOST "zfs destroy -r -R $RPOOL@$snap"
          pruned=1
        fi
     fi

     # Save values of this snapshot for next pass
     lastYear="$year" ; lastMon="$mon" ; lastDay="$day" ; lastHour="$hour"
     lastMin="$min" ; lastSec="$sec"; lastWeek="$week"

  done
  echo "##### END AUTOPRUNE"

fi
