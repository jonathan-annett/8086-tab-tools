#!/bin/sh
#
# Install `ping` on an ELKS machine — fetch the source, build it with the C
# compiler that ships on the image, install it.
#
#   urlget http://raw.githubusercontent.com:443/jonathan-annett/8086-tab-tools/main/install-ping.sh | sh
#
# (On 8086-tab.net the `:443` suffix tells the emulator's gateway to fetch
# over HTTPS. The guest speaks plain HTTP/1.0 and never learns TLS exists.)
#
# REVISIONS. REV below is the revision of ping.c this installer ships. The
# marker is a FILE whose NAME carries the revision — pingrev$REV — because
# ELKS sh has no $(...) to compare a version string with, but `test -f` is
# plenty when the version is in the filename:
#
#   /etc/pingrev$REV   -> this machine's /bin/ping is rev $REV
#   $work/pingrev$REV  -> the workshop's ping + ping.c are rev $REV
#
# No marker means STALE. A stale /bin/ping gets reinstalled; a stale
# workshop gets cleared and re-fetched. Without this, a saved drive would
# restore its old binary forever — and rebuild the old bug from its old
# source — no matter what this repo ships. (rev 5: ping learned its real
# address from $LOCALIP and to answer ARP; before that, tab could not
# ping tab.)
#
# If /dev/hdb is mounted it becomes the workshop: the SOURCE is kept there
# next to the binary, so a rebuild never needs the network again, and an md5
# beside it says which source that binary was built from. Three paths, in
# order of cost:
#
#   /bin/ping present           -> nothing to do
#   binary on the drive, md5 ok -> copy it in. No network, no compiler.
#   source on the drive         -> build it. No network.
#   nothing                     -> download the source, then build.
#
# MEMORY. This is a 640K machine with ~472K free, and c86 wants most of it.
# `net start` brings up ktcp *and* telnetd *and* ftpd, and those three
# together leave so little that the shell cannot even fork ("net: Cannot
# fork"), let alone compile. So: the network comes down before the compiler
# goes up. It has to come down for ping anyway — ping drives the NIC
# directly, and a running ktcp drains every inbound frame before ping can
# see it.

REPO=http://raw.githubusercontent.com:443/jonathan-annett/8086-tab-tools/main
REV=5

if test -f /bin/ping
then
if test -f /etc/pingrev$REV
then
echo "ping: already installed (rev $REV)"
exit 0
fi
echo "ping: /bin/ping is older than rev $REV -- updating"
fi

# The workshop: the drive if we have one (things persist), else /tmp.
work=/tmp
if mount /dev/hdb /mnt 2>/dev/null
then
work=/mnt
echo "ping: using /dev/hdb as the workshop -- source and binary persist"
fi

# A stale workshop is worse than an empty one: an old binary would be
# restored forever, and an old source would rebuild the old bug. No
# marker for THIS rev -> clear the artifacts and start clean.
if test -f $work/pingrev$REV
then
echo "ping: the workshop is rev $REV -- current"
else
rm -f $work/ping $work/ping.c $work/pingrev*
fi

# 1. A binary on the drive (its rev vouched for above)? Just take it.
if test -f $work/ping
then
if test -f $work/ping.c
then
echo "ping: found a built ping on the drive"
cp $work/ping /bin/ping
rm -f /etc/pingrev*
echo $REV > /etc/pingrev$REV
echo "ping: installed /bin/ping (no compile needed)"
md5sum $work/ping.c
if test "$work" = /mnt
then
umount /mnt
fi
exit 0
fi
fi

# 2. Source on the drive? Build it — no network needed at all.
if test -f $work/ping.c
then
echo "ping: found ping.c on the drive -- building it, no download needed"
else
# 3. Nothing. Fetch the source (this is the only step that needs the net).
echo "ping: fetching ping.c from github..."
urlget $REPO/ping.c > $work/ping.c
if test -s $work/ping.c
then
echo "ping: got it."
else
echo "ping: download failed -- is the network up? (net start ne0)"
rm -f $work/ping.c
if test "$work" = /mnt
then
umount /mnt
fi
exit 1
fi
fi

# The compiler needs the memory the network daemons are holding.
echo "ping: stopping the network -- c86 needs that memory back"
net stop

echo "ping: building with the on-image c86 toolchain, please wait..."
cd $work

# Flags are the ones from the image's own /usr/src/Makefile.
cpp -0 -I/usr/include -I/usr/include/c86 ping.c -o ping.i
c86 -g -O -bas86 -separate=yes -warn=4 -lang=c99 -align=yes -stackopt=minimum -peep=all -stackcheck=no ping.i ping.as
as -0 -j ping.as -o ping.o
ld -0 -i -L/usr/lib -o ping ping.o -lc86

# Tidy the intermediates -- on a drive we only want the source and the binary.
rm -f ping.i ping.as ping.o

if test -f $work/ping
then
cp $work/ping /bin/ping
rm -f /etc/pingrev*
echo $REV > /etc/pingrev$REV
echo $REV > $work/pingrev$REV
echo "ping: installed /bin/ping"
md5sum ping.c
if test "$work" = /mnt
then
sync
umount /mnt
echo "ping: source and binary are on /dev/hdb -- press Save to keep them."
echo "ping: after that, every boot installs ping without a download."
fi
echo "ping: the network is DOWN (the compiler needed the memory)."
echo "ping: try 'ping elk' or 'ping cat', then 'net start ne0'"
else
echo "ping: BUILD FAILED -- the transcript above has the reason"
if test "$work" = /mnt
then
umount /mnt
fi
fi
