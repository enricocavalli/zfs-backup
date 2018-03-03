# What is zfs-backup

This script will rsync to a remote host then take zfs snapshots.
root permission on the destination host are assumed.

zfs snapshots are cloned to filsystems to be easly browsable.

Pruning in similar to Mac OSX TimeMachine (keep one hourly for the
last 24 hours, one daily for the last 30 days, one weekly for backup
older than 30 days).

ssh agent forwarding is reccomended.

Note: --inplace should generate smaller snapshots, but is not compatible with
--hard-links (in general). Some also aruge that "--inplace" generates more
fragmentation on copy-on-write filesystems.

zfs pool creation and optional encryption of devices is outside the scope of the present documentation.

# Configuration

    cp config.default config

Edit config setting senible options

The default is backup up from /. If you want to be more
specific you can create a file named sources.txt with the filesystem you want
to back up.

Custom exclusion can be set in exclusions.txt (these are in addition to
default-exclusions.txt)

# Delegate zfs permission

I use this settings on my `user`:

	zfs allow user clone,create,destroy,mount,snapshot fs
	sysctl vfs.usermount=1 # necessary on FreeBSD

