// unisoc-hciproxy: H:4 pass-through between the UWE5621's /dev/ttyBT0 and a pty that btattach
// hands to the kernel. It clears the "Read Default Link Policy Settings" bit (commands[5] & 0x10)
// in the controller's Read Local Supported Commands reply: the Marlin3E firmware advertises that
// command but answers it with status 0x12, which makes the kernel abort controller init.
//   unisoc-hciproxy /dev/ttyBT0 /run/unisoc-bt.pty     (prints the pty path, symlinked there)
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>

static void makeRaw(int fd) {
    struct termios tty;
    if (tcgetattr(fd, &tty) == 0) { cfmakeraw(&tty); tcsetattr(fd, TCSANOW, &tty); }
}

static int writeAll(int fd, const uint8_t *data, size_t length) {
    while (length) {
        ssize_t n = write(fd, data, length);
        if (n < 0) { if (errno == EINTR || errno == EAGAIN) continue; return -1; }
        data += n; length -= (size_t)n;
    }
    return 0;
}

// Reassembles H:4 packets from the controller so a reply can be edited before forwarding.
struct Parser { uint8_t packet[1100]; size_t have, need; };

static size_t headerLength(uint8_t type) {
    switch (type) { case 0x04: return 3; case 0x02: return 5; case 0x03: return 4; case 0x05: return 5; default: return 0; }
}

static size_t payloadLength(const uint8_t *p) {
    switch (p[0]) {
    case 0x04: return p[2];
    case 0x02: return (size_t)(p[3] | p[4] << 8);
    case 0x03: return p[3];
    case 0x05: return (size_t)((p[3] | p[4] << 8) & 0x3fff);
    default: return 0;
    }
}

static int verbose;

static void patch(uint8_t *p) {
    if (verbose && p[0] == 0x04) {
        fprintf(stderr, "ctl> event %#04x len %u", p[1], p[2]);
        if (p[1] == 0x0e && p[2] >= 4) fprintf(stderr, " opcode %#06x status %#04x", p[4] | p[5] << 8, p[6]);
        if (p[1] == 0x0e && p[4] == 0x02 && p[5] == 0x10 && p[2] > 12) fprintf(stderr, " commands[5]=%#04x", p[7 + 5]);
        fprintf(stderr, "\n");
    }
    // Event 0x0e Command Complete, opcode 0x1002, status 0: params = num_cmds, opcode(2), status, commands[64]
    if (p[0] == 0x04 && p[1] == 0x0e && p[2] >= 1 + 2 + 1 + 64 && p[4] == 0x02 && p[5] == 0x10 && p[6] == 0x00) {
        uint8_t *commands = p + 7;
        if (commands[5] & 0x10) {
            commands[5] &= (uint8_t)~0x10;
            fprintf(stderr, "cleared Read Default Link Policy from supported commands\n");
        }
    }
}

// Feeds controller bytes; forwards complete packets (patched) to the host side.
static int feed(struct Parser *s, const uint8_t *data, size_t length, int host) {
    for (size_t i = 0; i < length; i++) {
        if (s->have == 0) {
            size_t header = headerLength(data[i]);
            if (!header) { writeAll(host, &data[i], 1); continue; }  // unknown: pass through untouched
            s->need = header;
        }
        s->packet[s->have++] = data[i];
        if (s->have == headerLength(s->packet[0])) {
            s->need = s->have + payloadLength(s->packet);
            if (s->need > sizeof s->packet) { writeAll(host, s->packet, s->have); s->have = 0; continue; }
        }
        if (s->have == s->need && s->have >= headerLength(s->packet[0])) {
            patch(s->packet);
            if (writeAll(host, s->packet, s->have) < 0) return -1;
            s->have = 0;
        }
    }
    return 0;
}

int main(int argc, char **argv) {
    if (argc != 3) { fprintf(stderr, "usage: %s /dev/ttyBT0 /run/link\n", argv[0]); return 2; }
    verbose = getenv("HCIPROXY_VERBOSE") != NULL;
    int controller = open(argv[1], O_RDWR | O_NOCTTY);
    if (controller < 0) { perror(argv[1]); return 1; }
    makeRaw(controller);
    int master = posix_openpt(O_RDWR | O_NOCTTY);
    if (master < 0 || grantpt(master) || unlockpt(master)) { perror("pty"); return 1; }
    const char *slave = ptsname(master);
    int keep = open(slave, O_RDWR | O_NOCTTY);  // keep the slave open so the master never sees EOF
    makeRaw(keep);
    unlink(argv[2]);
    if (symlink(slave, argv[2])) perror("symlink");
    printf("%s\n", slave);
    fflush(stdout);
    struct Parser parser = {0};
    uint8_t buffer[1024];
    for (;;) {
        struct pollfd fds[2] = {{controller, POLLIN, 0}, {master, POLLIN, 0}};
        if (poll(fds, 2, -1) < 0) { if (errno == EINTR) continue; perror("poll"); return 1; }
        if (fds[0].revents & (POLLIN | POLLHUP | POLLERR)) {
            ssize_t n = read(controller, buffer, sizeof buffer);
            if (n <= 0) { if (n < 0 && errno == EAGAIN) continue; fprintf(stderr, "controller closed\n"); return 1; }
            if (feed(&parser, buffer, (size_t)n, master) < 0) return 1;
        }
        if (fds[1].revents & POLLIN) {
            ssize_t n = read(master, buffer, sizeof buffer);
            if (verbose && n >= 4 && buffer[0] == 0x01) fprintf(stderr, "host> cmd %#06x len %u\n", buffer[1] | buffer[2] << 8, buffer[3]);
            if (n > 0 && writeAll(controller, buffer, (size_t)n) < 0) { perror("write controller"); return 1; }
        }
    }
}
