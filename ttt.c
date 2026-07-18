/*
 * ttt — two-machine tic-tac-toe for ELKS on the Tab Area Network.
 *
 *   server:  ttt          waits on port 3333, plays X, moves first
 *   client:  ttt HOST     connects to HOST (name or dotted IP), plays O
 *
 * Wire protocol: one ASCII digit '1'..'9' per move, strict
 * alternation, X first. No select(), no signals, no curses — a
 * blocking read IS the "waiting for opponent" spinner on a 4.77 MHz
 * machine, and printf is the display. Built by the image's own c86
 * toolchain; see install-ttt.sh.
 *
 * The image ships no socket headers (verified live 2026-07-18), so
 * the externs below are the ping.c idiom, and the constants come
 * from the ELKS source itself. Two that would bite a porter:
 * AF_INET is 0 on ELKS (not 2), and sin_port wants network order on
 * a little-endian 8086 — SWAP16 below.
 *
 * The socket calls resolve inside /usr/lib/libc86.a (the c86 libc
 * build includes net/ — in_gethostbyname reads /etc/hosts, so
 * `ttt cat` works wherever `ping cat` does).
 */

#include <stdio.h>
#include <string.h>

extern int socket();
extern int bind();
extern int listen();
extern int accept();
extern int connect();
extern int read();
extern int write();
extern int close();
extern unsigned long in_gethostbyname();

#define AF_INET     0   /* ELKS: linuxmt/socket.h — NOT the BSD 2 */
#define SOCK_STREAM 1
#define TTT_PORT    3333

#define SWAP16(x) ((unsigned short)((((x) & 0xffU) << 8) | (((x) >> 8) & 0xffU)))

/* linuxmt/in.h layout: family, port (network order), 32-bit addr. */
struct sockaddr_in {
    unsigned short sin_family;
    unsigned short sin_port;
    unsigned long  sin_addr;
};

static char board[10];          /* [1..9]; holds '1'..'9' or 'X'/'O' */
static struct sockaddr_in addr; /* static: c86-friendly, starts zeroed */

static void render(void)
{
    printf("\n");
    printf("  %c | %c | %c\n", board[1], board[2], board[3]);
    printf(" ---+---+---\n");
    printf("  %c | %c | %c\n", board[4], board[5], board[6]);
    printf(" ---+---+---\n");
    printf("  %c | %c | %c\n\n", board[7], board[8], board[9]);
}

static int winner(void)
{
    static int line[8][3] = {
        {1,2,3}, {4,5,6}, {7,8,9},   /* rows */
        {1,4,7}, {2,5,8}, {3,6,9},   /* columns */
        {1,5,9}, {3,5,7}             /* diagonals */
    };
    int i;
    for (i = 0; i < 8; i++) {
        char a = board[line[i][0]];
        if (a == board[line[i][1]] && a == board[line[i][2]])
            return 1;               /* a==digit can't triple: cells differ */
    }
    return 0;
}

static int full(void)
{
    int i;
    for (i = 1; i <= 9; i++)
        if (board[i] != 'X' && board[i] != 'O')
            return 0;
    return 1;
}

/* Read my move from the keyboard until it names a free cell. */
static int my_move(void)
{
    char buf[16];
    int cell;
    for (;;) {
        printf("your move (1-9): ");
        if (fgets(buf, sizeof(buf), stdin) == NULL)
            return -1;
        cell = buf[0] - '0';
        if (cell >= 1 && cell <= 9 && board[cell] != 'X' && board[cell] != 'O')
            return cell;
        printf("cell taken or not 1-9 -- again.\n");
    }
}

int main(int argc, char **argv)
{
    int fd, sock, cell, n, i, mine;
    char me, them, turn, ch;
    unsigned long ip;

    for (i = 1; i <= 9; i++)
        board[i] = (char)('0' + i);

    if (argc < 2) {
        /* ---- server: bind, wait, play X ---- */
        struct sockaddr_in peer;
        int len = sizeof(peer);
        me = 'X';
        them = 'O';
        sock = socket(AF_INET, SOCK_STREAM, 0);
        if (sock < 0) {
            printf("ttt: socket failed (is ktcp running? net start ne0)\n");
            return 1;
        }
        addr.sin_family = AF_INET;
        addr.sin_port = SWAP16(TTT_PORT);
        addr.sin_addr = 0;          /* INADDR_ANY */
        if (bind(sock, &addr, sizeof(addr)) < 0) {
            printf("ttt: bind failed (port %d busy?)\n", TTT_PORT);
            return 1;
        }
        listen(sock, 1);
        printf("ttt: waiting for a challenger on port %d ...\n", TTT_PORT);
        printf("     (they run: ttt <your-name-or-ip>)\n");
        fd = accept(sock, &peer, &len);
        if (fd < 0) {
            printf("ttt: accept failed\n");
            return 1;
        }
        printf("ttt: challenger connected -- you are X, you start.\n");
    } else {
        /* ---- client: resolve, connect, play O ---- */
        me = 'O';
        them = 'X';
        ip = in_gethostbyname(argv[1]);
        if (ip == 0 || ip == 0xffffffffUL) {
            printf("ttt: cannot resolve '%s'\n", argv[1]);
            return 1;
        }
        fd = socket(AF_INET, SOCK_STREAM, 0);
        if (fd < 0) {
            printf("ttt: socket failed (is ktcp running? net start ne0)\n");
            return 1;
        }
        addr.sin_family = AF_INET;
        addr.sin_port = SWAP16(TTT_PORT);
        addr.sin_addr = ip;
        printf("ttt: connecting to %s ...\n", argv[1]);
        if (connect(fd, &addr, sizeof(addr)) < 0) {
            printf("ttt: connect failed (is their ttt waiting?)\n");
            return 1;
        }
        printf("ttt: connected -- you are O, X starts.\n");
    }

    turn = 'X';
    for (;;) {
        render();
        mine = (turn == me);
        if (mine) {
            cell = my_move();
            if (cell < 0)
                break;
            ch = (char)('0' + cell);
            if (write(fd, &ch, 1) != 1) {
                printf("ttt: connection lost.\n");
                break;
            }
        } else {
            printf("waiting for %c ...\n", them);
            n = read(fd, &ch, 1);
            if (n != 1) {
                printf("ttt: opponent hung up.\n");
                break;
            }
            cell = ch - '0';
            if (cell < 1 || cell > 9 ||
                board[cell] == 'X' || board[cell] == 'O') {
                printf("ttt: opponent sent an illegal move ('%c') -- game over.\n", ch);
                break;
            }
        }
        board[cell] = turn;
        if (winner()) {
            render();
            printf(mine ? "*** you win! ***\n" : "*** %c wins -- you lose. ***\n", them);
            break;
        }
        if (full()) {
            render();
            printf("a draw. shake hands.\n");
            break;
        }
        turn = (turn == 'X') ? 'O' : 'X';
    }

    close(fd);
    return 0;
}
