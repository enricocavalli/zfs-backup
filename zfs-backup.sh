#!/bin/bash

INSTALLDIR=$( (cd -P $(dirname $0) && pwd) )
. "$INSTALLDIR/config"

LIMIT_PRUNE=${LIMIT_PRUNE:-0}
RPOOL=${MOUNT_POINT#/}

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


SOURCES="/"
if [ -f "$INSTALLDIR/sources.txt" ]; then
  SOURCES="--files-from=\"$INSTALLDIR/sources.txt\" -r /"
fi

EXCLUSIONS="--exclude-from=\"$INSTALLDIR/default-exclusions.txt\""
[ -f "$INSTALLDIR/exclusions.txt" ] && EXCLUSIONS="${EXCLUSIONS} --exclude-from=\"$INSTALLDIR/exclusions.txt\""

# repeat hourly or retry sooner if something fails
while true
do

mkdir -p "$INSTALLDIR/logs"

global_return=0
if ! ssh $REMOTE_USER@$REMOTEHOST "[ -d $MOUNT_POINT ]"
  then
  echo "Remote filesystem not mounted"
  global_return=1
fi

now="$(date +%Y-%m-%d-%H%M%S)"

if [ $global_return -eq 0 ]; then

eval nice -n 20 rsync \
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

  ssh $REMOTE_USER@$REMOTEHOST "zfs snapshot -r $RPOOL@$now"

  curEpoc=`date +%s`
  lastYear=""; lastMon=""; lastDay=""; lastHour="" lastMin="" ; lastSec=""
  # Get our list of snaps
  snaps=$(ssh $REMOTE_USER@$REMOTEHOST "zfs list -d 1 -t snapshot -H $RPOOL" | cut -f 1 | cut -d '@' -f 2 | grep -v ^auto-)

  pruned_num=0
  rSnaps=""

  # Reverse the list, sort from newest to oldest
  for tmp in $snaps
  do
     rSnaps="$tmp $rSnaps" # reverse order
  done

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
          pruned_num=`expr $pruned_num +  1`
        fi
     fi

     # Looking for multiple snaps older than a day
     if [ $check -gt 86400 -a $pruned -eq 0 ]; then
        if [ "$week" = "$lastWeek" -a "$day" = "$lastDay" ] ; then
          echo "Destroy $snap"
          ssh $REMOTE_USER@$REMOTEHOST "zfs destroy -r -R $RPOOL@$snap"
          pruned=1
          pruned_num=`expr $pruned_num +  1`
        fi
     fi

     # Looking for multiple snaps older than an hour
     if [ $check -gt 3600 -a $pruned -eq 0 ]; then
        if [ "$week" = "$lastWeek" -a "$day" = "$lastDay" -a "$hour" = "$lastHour" ] ; then
          echo "Destroy $snap"
          ssh $REMOTE_USER@$REMOTEHOST "zfs destroy -r -R $RPOOL@$snap"
          pruned=1
          pruned_num=`expr $pruned_num +  1`
        fi
     fi

     # break if pruned=1 conditionally if only one prune per run is desider (let it be a configuration choice)
     if [  $LIMIT_PRUNE -gt 0 -a $pruned_num -ge $LIMIT_PRUNE ]; then
       break
     fi

     # Save values of this snapshot for next pass
     lastYear="$year" ; lastMon="$mon" ; lastDay="$day" ; lastHour="$hour"
     lastMin="$min" ; lastSec="$sec"; lastWeek="$week"

  done
  sleep 3600

else
global_return=1
fi
fi

if [ ! $global_return -eq 0 ]; then
  # sleep 10 seconds if something failed and restart
  sleep 10
fi

done
