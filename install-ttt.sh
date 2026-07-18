#!/bin/sh
#
# Install `ttt` — two-machine tic-tac-toe over the Tab Area Network.
# Fetch the source, build it with the C compiler that ships on the
# image, install it. The dogfood loop made flesh: a repo on github,
# downloaded, built, run — the platform extending itself.
#
#   urlget http://raw.githubusercontent.com:443/jonathan-annett/8086-tab-tools/main/install-ttt.sh | sh
#
# Then on one machine:  ttt          (waits, plays X)
# and on another:       ttt <name>   (e.g. `ttt mouse` — /etc/hosts
#                                     names work wherever ping's do)
#
# Structure and hard-won lessons inherited from install-ping.sh: the
# rev-in-filename marker (ELKS sh has no $(...)), the drive-as-
# workshop, and the MEMORY discipline — c86 wants the RAM the network
# daemons hold, so the net comes down for the compile. Difference
# from ping: ttt NEEDS ktcp to play, so the last line of a successful
# install reminds you to `net start ne0` before the game.

REPO=http://raw.githubusercontent.com:443/jonathan-annett/8086-tab-tools/main
REV=1

if test -f /bin/ttt
then
if test -f /etc/tttrev$REV
then
echo "ttt: already installed (rev $REV)"
exit 0
fi
echo "ttt: /bin/ttt is older than rev $REV -- updating"
fi

work=/tmp
if mount /dev/hdb /mnt 2>/dev/null
then
work=/mnt
echo "ttt: using /dev/hdb as the workshop -- source and binary persist"
fi

if test -f $work/tttrev$REV
then
echo "ttt: the workshop is rev $REV -- current"
else
rm -f $work/ttt $work/ttt.c $work/tttrev*
fi

if test -f $work/ttt
then
if test -f $work/ttt.c
then
echo "ttt: found a built ttt on the drive"
cp $work/ttt /bin/ttt
rm -f /etc/tttrev*
echo $REV > /etc/tttrev$REV
echo "ttt: installed /bin/ttt (no compile needed)"
if test "$work" = /mnt
then
umount /mnt
fi
echo "ttt: find an opponent -- 'ttt' hosts, 'ttt <name>' joins."
exit 0
fi
fi

if test -f $work/ttt.c
then
echo "ttt: found ttt.c on the drive -- building it, no download needed"
else
echo "ttt: fetching ttt.c from github..."
urlget $REPO/ttt.c > $work/ttt.c
if test -s $work/ttt.c
then
echo "ttt: got it."
else
echo "ttt: download failed -- is the network up? (net start ne0)"
rm -f $work/ttt.c
if test "$work" = /mnt
then
umount /mnt
fi
exit 1
fi
fi

# (XMS-era machines keep the net UP through the compile -- Jonathan's
# ruling 2026-07-18: the daemons no longer starve c86. On an older
# non-XMS machine a memory failure here is what `net stop` is for.)
echo "ttt: building with the on-image c86 toolchain, please wait..."
cd $work

cpp -0 -I/usr/include -I/usr/include/c86 ttt.c -o ttt.i
c86 -g -O -bas86 -separate=yes -warn=4 -lang=c99 -align=yes -stackopt=minimum -peep=all -stackcheck=no ttt.i ttt.as
as -0 -j ttt.as -o ttt.o
ld -0 -i -L/usr/lib -o ttt ttt.o -lc86

rm -f ttt.i ttt.as ttt.o

if test -f $work/ttt
then
cp $work/ttt /bin/ttt
rm -f /etc/tttrev*
echo $REV > /etc/tttrev$REV
echo $REV > $work/tttrev$REV
echo "ttt: installed /bin/ttt"
md5sum ttt.c
sync
if test "$work" = /mnt
then
umount /mnt
echo "ttt: source and binary are on /dev/hdb -- press Save to keep them."
fi
echo "ttt: run 'ttt' to host a game, or 'ttt <name>' to join one."
else
echo "ttt: BUILD FAILED -- the transcript above has the reason"
echo "ttt: (a memory failure? 'net stop' frees the daemons' RAM, then re-run)"
if test "$work" = /mnt
then
umount /mnt
fi
fi
