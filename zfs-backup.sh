#!/bin/sh

INSTALLDIR=$( (cd -P $(dirname $0) && pwd) )
. "$INSTALLDIR/config"

mkdir -p "$INSTALLDIR/logs"

if ! $SSH root@$REMOTEHOST "[ -d /$RPOOL/.rsync ]"
  then
  echo "Remote filesystem not mounted"
  exit 1
fi

SOURCES="/"
if [ -f "sources.txt" ]; then
  SOURCES="--files-from=$INSTALLDIR/sources.txt -r /"
fi

echo "Checking sudo execution"
sudo true || exit 1

CUSTOM_EXCLUSIONS=""
[ -f "./exclusions.txt" ] && CUSTOM_EXCLUSIONS="--exclude-from=$INSTALLDIR/exclusions.txt"

now="$(date +%Y-%m-%d-%H%M%S)"

echo "Please enter you password for 'sudo' if requested."
echo "##### BEGIN RSYNC"
sudo nice -n 20 rsync \
-e "$SSH -i $KEYFILEPATH" \
--log-file="$INSTALLDIR/logs/sync.log" \
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
--exclude-from="$INSTALLDIR/default-exclusions.txt" "$CUSTOM_EXCLUSIONS" \
$SOURCES root@$REMOTEHOST:/$RPOOL/.rsync/

return=$?
echo "##### END RSYNC"

if [ $return -eq 0 -o $return -eq 24 ]; then
  echo "##### BEGIN AUTOPRUNE"
  $SSH root@$REMOTEHOST "zfs snapshot -r $RPOOL/.rsync@$now && zfs clone $RPOOL/.rsync@$now $RPOOL/$now"


  # determine the last synced snapshot
  lastSEND=$($SSH root@$REMOTEHOST "zfs get -d 1 -H -t snapshot zfs-backup:synced $RPOOL/.rsync" | awk '($3 ~ "true") {print $0}' | tail -1 | cut -f 1 | cut -d '@' -f 2)

  if [ -n "$lastSEND" ] ; then
  sec="${lastSEND:15:2}"
  min="${lastSEND:13:2}"
  hour="${lastSEND:11:2}"
  day="${lastSEND:8:2}"
  mon="${lastSEND:5:2}"
  year="${lastSEND:0:4}"

  sendEpoc=`date -j -f "%Y %m %d %H %M %S" "$year $mon $day $hour $min $sec" "+%s"`
  fi
  curEpoc=`date +%s`
  lastYear=""; lastMon=""; lastDay=""; lastHour="" lastMin="" ; lastSec=""
  # Get our list of snaps
  snaps=$($SSH root@$REMOTEHOST "zfs list -d 1 -t snapshot -H $RPOOL/.rsync" | cut -f 1 | cut -d '@' -f 2)

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
     snapEpoc=`date -j -f "%Y %m %d %H %M %S" "$year $mon $day $hour $min $sec" "+%s"`
     week=`date -j -f "%Y %m %d %H %M %S" "$year $mon $day $hour $min $sec" "+%G%V"`


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
     #   $SSH root@$REMOTEHOST "zfs destroy -r  data@$snap"
     #   pruned=1
     #fi

     # Looking for multiple snaps older than 30 days
     if [ $check -gt 2592000 -a $pruned -eq 0 ]; then
        # Did we already have a snapshot from this week?
        if [ "$week" = "$lastWeek" ] ; then
          echo "Destroy $snap"
          $SSH root@$REMOTEHOST "zfs destroy -r -R $RPOOL/.rsync@$snap"
          pruned=1
        fi
     fi

     # Looking for multiple snaps older than a day
     if [ $check -gt 86400 -a $pruned -eq 0 ]; then
        if [ "$week" = "$lastWeek" -a "$day" = "$lastDay" ] ; then
          echo "Destroy $snap"
          $SSH root@$REMOTEHOST "zfs destroy -r -R $RPOOL/.rsync@$snap"
          pruned=1
        fi
     fi

     # Looking for multiple snaps older than an hour
     if [ $check -gt 3600 -a $pruned -eq 0 ]; then
        if [ "$week" = "$lastWeek" -a "$day" = "$lastDay" -a "$hour" = "$lastHour" ] ; then
          echo "Destroy $snap"
          $SSH root@$REMOTEHOST "zfs destroy -r -R $RPOOL/.rsync@$snap"
          pruned=1
        fi
     fi

     # Save values of this snapshot for next pass
     lastYear="$year" ; lastMon="$mon" ; lastDay="$day" ; lastHour="$hour"
     lastMin="$min" ; lastSec="$sec"; lastWeek="$week"

  done
  echo "##### END AUTOPRUNE"

  if [ -n "$REPLICA_HOST" ]; then
    if ! $SSH root@$REPLICA_HOST "[ -d /$REPLICA_POOL/.rsync ]"
    then
      echo "Replica filesystem not mounted"
      exit 1
    fi
    echo "##### BEGIN REPLICA"
    $INSTALLDIR/replica.sh
    echo "##### END REPLICA"
  fi

fi
