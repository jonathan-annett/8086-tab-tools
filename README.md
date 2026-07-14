# 8086-tab-tools

Small tools for **ELKS** (Embeddable Linux Kernel Subset) running on a
16-bit 8086 — written to be compiled *by the machine itself*, with the
C86 toolchain that ships on the ELKS hard-disk image.

They were built for [8086-tab.net](https://8086-tab.net), a pure-TypeScript
8086 emulator that boots real ELKS in a browser tab, but there is nothing
browser-specific in here: this is ordinary ELKS userland C. If you have an
ELKS machine — emulated or a genuine XT — these should build and run.

## The tools

| tool | what it is |
|---|---|
| [`ping.c`](ping.c) | ICMP ping. ELKS doesn't ship one, so this is it. |

### ping

ELKS has no `ping`: its TCP/IP daemon `ktcp` handles ICMP echo *replies*
but never originates them, and exposes no ICMP socket API. So this tool
goes **under** the stack — it opens the ethernet device (`/dev/ne0`)
directly and does its own ARP, its own IP and ICMP framing, and its own
checksums, in about 400 lines with no dependencies beyond `<stdio.h>`.

```
# ping gateway
PING 10.0.2.2 from 10.0.2.15: 32 data bytes
40 bytes from 10.0.2.2: seq=1 time=0 ms
40 bytes from 10.0.2.2: seq=2 time=0 ms
40 bytes from 10.0.2.2: seq=3 time=0 ms
--- 10.0.2.2 ping statistics ---
3 packets transmitted, 3 received
```

Usage: `ping ADDR|NAME [count]`

**It needs the NIC to itself.** `ktcp` holds the ethernet device open and
drains every inbound frame, so while networking is up, ping's replies are
eaten before it can see them. Run it *before* `net start`, or:

```
net stop
ping gateway
net start ne0
```

Names come from `/etc/hosts`, deliberately **not** DNS — the ELKS resolver
speaks DNS-over-TCP through `ktcp` (there is no UDP in the stack at all),
and `ktcp` is precisely the process that must not be running. A file read
needs no network stack, and the stock image already lists `gateway` and
`elks15`/`elks16`/`elks17`, which is the neighbourhood worth pinging.

Portability notes, learned the hard way:

- The ELKS ABI bits it needs (`O_RDWR`, `IOCTL_ETH_ADDR_GET`,
  `struct timeval`, `fd_set` as a 32-bit mask) are **self-declared** in the
  source, because the hard-disk image ships only the C86 subset of
  `/usr/include`.
- stdio is fully buffered, so the code `fflush`es at progress points —
  otherwise a hang prints nothing at all.
- Device node is `/dev/ne0` on current images (`/dev/eth` on older ones);
  it tries both.

## Building it, on the machine, with the machine

The ELKS hard-disk image ships a native C compiler. No cross-compiler, no
host toolchain — the 8086 builds its own tools:

```sh
cpp -0 -I/usr/include -I/usr/include/c86 ping.c -o ping.i
c86 -g -O -bas86 -separate=yes -warn=4 -lang=c99 -align=yes \
    -stackopt=minimum -peep=all -stackcheck=no ping.i ping.as
as -0 -j ping.as -o ping.o
ld -0 -i -L/usr/lib -o ping ping.o -lc86
cp ping /bin/ping
```

(The flags are the ones from the image's own `/usr/src/Makefile`.)

## Getting the source onto the machine

If your ELKS box can reach the network, it can fetch straight from here —
`raw.githubusercontent.com` serves permissive CORS, which matters when the
"network" is a browser tab:

```sh
urlget http://raw.githubusercontent.com:443/jonathan-annett/8086-tab-tools/main/ping.c > ping.c
```

On [8086-tab.net](https://8086-tab.net) the `:443` suffix tells the
emulator's gateway to fetch over HTTPS — the guest speaks plain HTTP/1.0
on the wire and never has to know TLS exists.

## License

MIT — see [LICENSE](LICENSE). Do what you like with them.
