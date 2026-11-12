// regs: read/write 32-bit MMIO registers through /dev/mem (root only).
//   regs read  ADDR [COUNT]   dump COUNT words from ADDR
//   regs write ADDR VALUE     write one word, print old -> new
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: regs read ADDR [COUNT] | regs write ADDR VALUE\n");
        return 2;
    }
    const uint64_t address = strtoull(argv[2], NULL, 0);
    const int writing = strcmp(argv[1], "write") == 0;
    const long count = writing ? 1 : (argc > 3 ? strtol(argv[3], NULL, 0) : 1);
    const long page = sysconf(_SC_PAGESIZE);
    const uint64_t base = address & ~(uint64_t)(page - 1);
    const size_t length = (size_t)(address - base) + (size_t)count * 4;
    const int fd = open("/dev/mem", (writing ? O_RDWR : O_RDONLY) | O_SYNC);
    if (fd < 0) {
        perror("/dev/mem");
        return 1;
    }
    void *map = mmap(NULL, length, writing ? PROT_READ | PROT_WRITE : PROT_READ, MAP_SHARED, fd, (off_t)base);
    if (map == MAP_FAILED) {
        perror("mmap");
        return 1;
    }
    volatile uint32_t *words = (volatile uint32_t *)((char *)map + (address - base));
    if (writing) {
        const uint32_t old = words[0];
        words[0] = (uint32_t)strtoul(argv[3], NULL, 0);
        printf("%#010llx: %#010x -> %#010x\n", (unsigned long long)address, old, words[0]);
    } else {
        for (long index = 0; index < count; index++) {
            printf("%#010llx: %#010x\n", (unsigned long long)(address + index * 4), words[index]);
        }
    }
    munmap(map, length);
    close(fd);
    return 0;
}
