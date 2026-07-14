#!/bin/sh
#
# Install `ping` on an ELKS machine — fetch the source, build it with the
# C compiler that ships on the image, install it.
#
# With the network up:
#
#   urlget http://raw.githubusercontent.com:443/jonathan-annett/8086-tab-tools/refs/heads/main/install-ping.sh | sh
#
# (On 8086-tab.net the `:443` suffix tells the emulator's gateway to fetch
# over HTTPS. The guest speaks plain HTTP/1.0 and never learns TLS exists.)
#
# Idempotent — safe to run at every boot:
#
#   /bin/ping present         -> nothing to do
#   a saved copy on /dev/hdb  -> restore it, no compile
#   otherwise                 -> fetch ping.c, build it, install it, and
#                                stash a copy on /dev/hdb if one is mounted
#
# Run it with the network UP — it has to download. It then takes the network
# DOWN itself, for two reasons that happen to agree:
#
#   * c86 needs the memory that ktcp/telnetd/ftpd are holding. On a 640K
#     machine that is the difference between a build and "not enough memory".
#   * ping drives the NIC directly, and a running ktcp drains every inbound
#     frame before ping can see it.
#
# So when this finishes: ping, then `net start ne0` to get the network back.

REPO=http://raw.githubusercontent.com:443/jonathan-annett/8086-tab-tools/refs/heads/main
REV=4

if test -f /bin/ping
then
echo "ping: already installed"
exit 0
fi

drive=no
if mount /dev/hdb /mnt 2>/dev/null
then
drive=yes
fi

# The revision is in the marker's NAME, so the check is a plain `test -f`:
# ELKS sh has no $(...) command substitution to compare a version with.
if test -f /mnt/pingrev4
then
echo "ping: restoring the saved copy from /dev/hdb"
cp /mnt/ping /bin/ping
umount /mnt
exit 0
fi

if test -f /mnt/ping
then
echo "ping: the copy on /dev/hdb is out of date -- rebuilding"
fi

echo "ping: fetching ping.c from github..."
cd /tmp
urlget $REPO/ping.c > ping.c

if test -s ping.c
then
echo "ping: got it."
else
echo "ping: download failed -- is the network up? (net start ne0)"
if test "$drive" = yes
then
umount /mnt
fi
exit 1
fi

# The network was only ever needed for the download, and now it is in the
# way: ktcp, telnetd and ftpd are sitting on the memory c86 wants, and on
# a 640K machine that is the difference between a build and
# "c86: not enough memory". Take the stack down before compiling.
#
# It has to come down for ping anyway -- ping drives the NIC directly, and
# a running ktcp drains every inbound frame before ping can see it.
echo "ping: stopping the network -- the compiler needs that memory"
net stop

echo "ping: building with the on-image c86 toolchain, please wait..."

# Flags are the ones from the image's own /usr/src/Makefile.
cpp -0 -I/usr/include -I/usr/include/c86 ping.c -o ping.i
c86 -g -O -bas86 -separate=yes -warn=4 -lang=c99 -align=yes -stackopt=minimum -peep=all -stackcheck=no ping.i ping.as
as -0 -j ping.as -o ping.o
ld -0 -i -L/usr/lib -o ping ping.o -lc86

if test -f /tmp/ping
then
cp /tmp/ping /bin/ping
echo "ping: installed /bin/ping"
if test "$drive" = yes
then
cp /tmp/ping /mnt/ping
echo $REV > /mnt/pingrev4
sync
echo "ping: saved to /dev/hdb -- press Save in the browser to keep it"
fi
echo "ping: the network is DOWN (the compiler needed the memory)."
echo "ping: try 'ping elk' (the gateway) or 'ping cat', then 'net start ne0'"
else
echo "ping: BUILD FAILED -- the transcript above has the reason"
fi

if test "$drive" = yes
then
umount /mnt
fi
