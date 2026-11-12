// unisoc-btinit: Android libbt-vendor_uwe's vendor init for the UWE5621 (Marlin3E) Bluetooth core,
// done over the sprdbt_tty H:4 port before btattach hands it to the kernel:
//   0xFCA0 pskey block, 0xFCA2 RF block, 0xFCA1 {00 00 01} core enable.
// Without it the controller rejects standard init commands (0x080f -> status 0x12).
//   unisoc-btinit /dev/ttyBT0 pskey.bin rf.bin
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>

static int readExact(int fd, uint8_t *buffer, size_t length, int timeoutMs) {
    size_t got = 0;
    while (got < length) {
        struct pollfd p = {fd, POLLIN, 0};
        if (poll(&p, 1, timeoutMs) <= 0) return -1;
        ssize_t n = read(fd, buffer + got, length - got);
        if (n <= 0) return -1;
        got += (size_t)n;
    }
    return 0;
}

// Sends one HCI command and waits for its Command Complete / Command Status; returns HCI status.
static int command(int fd, uint16_t opcode, const uint8_t *params, uint8_t length) {
    uint8_t packet[260] = {0x01, (uint8_t)(opcode & 0xff), (uint8_t)(opcode >> 8), length};
    memcpy(packet + 4, params, length);
    if (write(fd, packet, 4u + length) != 4 + length) { perror("write"); return -1; }
    for (int events = 0; events < 8; events++) {
        uint8_t header[3];
        if (readExact(fd, header, 3, 3000) < 0) { fprintf(stderr, "%#06x: no reply\n", opcode); return -1; }
        uint8_t body[255];
        if (header[0] != 0x04 || readExact(fd, body, header[2], 1000) < 0) { fprintf(stderr, "%#06x: bad packet %02x\n", opcode, header[0]); return -1; }
        if (header[1] == 0x0e && header[2] >= 4 && (body[1] | body[2] << 8) == opcode) {  // Command Complete
            printf("%#06x (%u bytes): status %#04x\n", opcode, length, body[3]);
            return body[3];
        }
        if (header[1] == 0x0f && header[2] >= 4 && (body[2] | body[3] << 8) == opcode) {  // Command Status
            printf("%#06x (%u bytes): command status %#04x\n", opcode, length, body[0]);
            return body[0];
        }
    }
    fprintf(stderr, "%#06x: no matching event\n", opcode);
    return -1;
}

static int load(const char *path, uint8_t *buffer, size_t capacity) {
    FILE *file = fopen(path, "rb");
    if (!file) { perror(path); return -1; }
    size_t n = fread(buffer, 1, capacity, file);
    fclose(file);
    return (int)n;
}

int main(int argc, char **argv) {
    if (argc != 4) { fprintf(stderr, "usage: %s /dev/ttyBT0 pskey.bin rf.bin\n", argv[0]); return 2; }
    uint8_t pskey[255], rf[255];
    int pskeyLength = load(argv[2], pskey, sizeof pskey), rfLength = load(argv[3], rf, sizeof rf);
    if (pskeyLength <= 0 || rfLength <= 0) return 1;
    int fd = open(argv[1], O_RDWR | O_NOCTTY);
    if (fd < 0) { perror(argv[1]); return 1; }
    struct termios tty;
    if (tcgetattr(fd, &tty) == 0) { cfmakeraw(&tty); tcsetattr(fd, TCSANOW, &tty); }
    tcflush(fd, TCIOFLUSH);
    const uint8_t enable[3] = {0x00, 0x00, 0x01};
    int failures = 0;
    failures += command(fd, 0xfca0, pskey, (uint8_t)pskeyLength) != 0;
    failures += command(fd, 0xfca2, rf, (uint8_t)rfLength) != 0;
    failures += command(fd, 0xfca1, enable, sizeof enable) != 0;
    close(fd);
    return failures ? 1 : 0;
}
