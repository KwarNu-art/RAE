#define _GNU_SOURCE
#include "RAEMachO.h"
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#define MH_MAGIC_64 0xfeedfacfu
#define FAT_MAGIC 0xcafebabeu
#define CPU_TYPE_ARM64 0x0100000Cu

#define LC_SEGMENT_64 0x19u
#define LC_SYMTAB 0x2u
#define LC_UUID 0x1Bu
#define LC_LOAD_DYLIB 0xCu
#define LC_LOAD_WEAK_DYLIB 0x80000018u
#define LC_REEXPORT_DYLIB 0x8000001Fu
#define LC_LAZY_LOAD_DYLIB 0x20u
#define LC_ENCRYPTION_INFO 0x21u
#define LC_ENCRYPTION_INFO_64 0x2Cu
#define LC_VERSION_MIN_IPHONEOS 0x25u
#define LC_BUILD_VERSION 0x32u
#define LC_FUNCTION_STARTS 0x26u

#define MAX_IMPORTS 200000
#define MAX_CLASS_NAMES 600
#define MAX_LIBS 1024

static uint32_t rd32(const unsigned char *p) { return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24); }
static uint64_t rd64(const unsigned char *p) { return (uint64_t)rd32(p) | ((uint64_t)rd32(p + 4) << 32); }
static uint32_t rdbe32(const unsigned char *p) { return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3]; }

static void fail(RAEMachOInfo *info, const char *msg) {
    info->valid = 0;
    snprintf(info->error, sizeof(info->error), "%s", msg);
}

static int push(char ***list, size_t *count, size_t *cap, const char *s, size_t len) {
    if (*count == *cap) {
        size_t ncap = *cap ? *cap * 2 : 64;
        char **p = realloc(*list, ncap * sizeof(char *));
        if (!p) return -1;
        *list = p;
        *cap = ncap;
    }
    char *copy = malloc(len + 1);
    if (!copy) return -1;
    memcpy(copy, s, len);
    copy[len] = 0;
    (*list)[(*count)++] = copy;
    return 0;
}

static void copyName16(char *dst, const unsigned char *src) {
    memcpy(dst, src, 16);
    dst[16] = 0;
}

int RAEMachOParse(const char *path, RAEMachOInfo *info,
                  const char *const *needles, size_t needleCount, unsigned char *needleHits) {
    memset(info, 0, sizeof(*info));
    if (needleHits) memset(needleHits, 0, needleCount);

    int fd = open(path, O_RDONLY);
    if (fd < 0) { fail(info, "cannot open the executable"); return -1; }
    struct stat st;
    if (fstat(fd, &st) != 0 || st.st_size < 64) { close(fd); fail(info, "executable is empty"); return -1; }
    size_t fileSize = (size_t)st.st_size;
    const unsigned char *base = mmap(NULL, fileSize, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if (base == MAP_FAILED) { fail(info, "cannot map the executable"); return -1; }
    info->fileSize = fileSize;

    // Fat file: pick the arm64 slice.
    const unsigned char *img = base;
    size_t imgSize = fileSize;
    if (rdbe32(base) == FAT_MAGIC) {
        uint32_t n = rdbe32(base + 4);
        int found = 0;
        for (uint32_t i = 0; i < n && 8 + (size_t)(i + 1) * 20 <= fileSize; i++) {
            const unsigned char *a = base + 8 + (size_t)i * 20;
            if (rdbe32(a) == CPU_TYPE_ARM64) {
                uint32_t off = rdbe32(a + 8), size = rdbe32(a + 12);
                if ((uint64_t)off + size <= fileSize) { img = base + off; imgSize = size; found = 1; }
                break;
            }
        }
        if (!found) { munmap((void *)base, fileSize); fail(info, "no arm64 slice in this binary"); return -1; }
    }
    if (imgSize < 32 || rd32(img) != MH_MAGIC_64) {
        munmap((void *)base, fileSize);
        fail(info, "not a 64-bit Mach-O executable");
        return -1;
    }

    info->cputype = rd32(img + 4);
    info->cpusubtype = rd32(img + 8);
    uint32_t ncmds = rd32(img + 16);
    uint32_t sizeofcmds = rd32(img + 20);
    if (32 + (uint64_t)sizeofcmds > imgSize) { munmap((void *)base, fileSize); fail(info, "damaged load commands"); return -1; }

    size_t libCap = 0, impCap = 0, clsCap = 0, secCap = 0;
    uint32_t symoff = 0, nsyms = 0, stroff = 0, strsize = 0;
    uint32_t cryptoff = 0, cryptsize = 0;
    uint32_t fnOff = 0, fnSize = 0;

    // Pass 1: load commands.
    uint64_t pos = 32;
    for (uint32_t i = 0; i < ncmds && pos + 8 <= 32 + (uint64_t)sizeofcmds; i++) {
        const unsigned char *c = img + pos;
        uint32_t cmd = rd32(c), size = rd32(c + 4);
        if (size < 8 || pos + size > 32 + (uint64_t)sizeofcmds) break;

        switch (cmd) {
            case LC_SEGMENT_64: {
                if (size < 72) break;
                char seg[17];
                copyName16(seg, c + 8);
                uint64_t vmsize = rd64(c + 32);
                uint32_t nsects = rd32(c + 64);
                if (strcmp(seg, "__TEXT") == 0) info->textSize = vmsize;
                if (strcmp(seg, "__DATA") == 0 || strcmp(seg, "__DATA_CONST") == 0) info->dataSize += vmsize;
                for (uint32_t s = 0; s < nsects && 72 + (uint64_t)(s + 1) * 80 <= size; s++) {
                    const unsigned char *sec = c + 72 + (size_t)s * 80;
                    if (info->sectionCount == secCap) {
                        size_t ncap = secCap ? secCap * 2 : 32;
                        RAEMachOSection *p = realloc(info->sections, ncap * sizeof(RAEMachOSection));
                        if (!p) break;
                        info->sections = p;
                        secCap = ncap;
                    }
                    RAEMachOSection *out = &info->sections[info->sectionCount++];
                    copyName16(out->section, sec);
                    copyName16(out->segment, sec + 16);
                    out->size = rd64(sec + 40);
                }
                break;
            }
            case LC_SYMTAB:
                if (size >= 24) { symoff = rd32(c + 8); nsyms = rd32(c + 12); stroff = rd32(c + 16); strsize = rd32(c + 20); }
                break;
            case LC_UUID:
                if (size >= 24) {
                    static const char hex[] = "0123456789ABCDEF";
                    int o = 0;
                    for (int b = 0; b < 16; b++) {
                        if (b == 4 || b == 6 || b == 8 || b == 10) info->uuid[o++] = '-';
                        info->uuid[o++] = hex[c[8 + b] >> 4];
                        info->uuid[o++] = hex[c[8 + b] & 15];
                    }
                    info->uuid[o] = 0;
                }
                break;
            case LC_LOAD_DYLIB: case LC_LOAD_WEAK_DYLIB: case LC_REEXPORT_DYLIB: case LC_LAZY_LOAD_DYLIB: {
                if (size < 24 || info->libCount >= MAX_LIBS) break;
                uint32_t nameOff = rd32(c + 8);
                if (nameOff >= size) break;
                const char *name = (const char *)c + nameOff;
                size_t maxLen = size - nameOff;
                size_t len = strnlen(name, maxLen);
                push(&info->libs, &info->libCount, &libCap, name, len);
                break;
            }
            case LC_ENCRYPTION_INFO_64:
            case LC_ENCRYPTION_INFO:
                if (size >= 20 && rd32(c + 16) != 0) { info->encrypted = 1; cryptoff = rd32(c + 8); cryptsize = rd32(c + 12); }
                break;
            case LC_VERSION_MIN_IPHONEOS:
                if (size >= 16) { info->minOS = rd32(c + 8); info->sdk = rd32(c + 12); }
                break;
            case LC_BUILD_VERSION:
                if (size >= 24) { info->minOS = rd32(c + 12); info->sdk = rd32(c + 16); }
                break;
            case LC_FUNCTION_STARTS:
                if (size >= 16) { fnOff = rd32(c + 8); fnSize = rd32(c + 12); }
                break;
            default: break;
        }
        pos += size;
    }

    // Function count: the function-starts table is a run of ULEB128 deltas ended by 0.
    if (fnSize && (uint64_t)fnOff + fnSize <= imgSize) {
        const unsigned char *p = img + fnOff, *end = p + fnSize;
        uint64_t count = 0;
        int nonZero = 0;
        while (p < end) {
            unsigned char b = *p++;
            if (b & 0x7f) nonZero = 1;
            if (!(b & 0x80)) {                  // end of one ULEB128 value
                if (!nonZero) break;            // a zero value ends the table
                count++;
                nonZero = 0;
            }
        }
        info->functionCount = count;
    }

    // Pass 2: symbols. Undefined external symbols are the APIs this binary calls.
    if (nsyms && (uint64_t)symoff + (uint64_t)nsyms * 16 <= imgSize && (uint64_t)stroff + strsize <= imgSize) {
        const unsigned char *syms = img + symoff;
        const char *strtab = (const char *)img + stroff;
        for (uint32_t s = 0; s < nsyms; s++) {
            const unsigned char *n = syms + (size_t)s * 16;
            uint32_t strx = rd32(n);
            unsigned char type = n[4];
            if (strx == 0 || strx >= strsize) continue;
            const char *name = strtab + strx;
            size_t len = strnlen(name, strsize - strx);
            if (len == 0) continue;
            if ((type & 0x01) && (type & 0x0e) == 0) {                         // undefined, external
                if (info->importCount < MAX_IMPORTS) push(&info->imports, &info->importCount, &impCap, name, len);
            } else if ((type & 0x01) && (type & 0x0e) == 0x0e) {               // defined in a section, external
                if (len > 14 && strncmp(name, "_OBJC_CLASS_$_", 14) == 0) {
                    info->classTotal++;
                    if (info->classCount < MAX_CLASS_NAMES) push(&info->classes, &info->classCount, &clsCap, name + 14, len - 14);
                }
            }
        }
    }

    // Pass 3: string sections. Skip the encrypted range so a still-encrypted binary is not misread.
    if (needles && needleHits && needleCount) {
        uint64_t p2 = 32;
        for (uint32_t i = 0; i < ncmds && p2 + 8 <= 32 + (uint64_t)sizeofcmds; i++) {
            const unsigned char *c = img + p2;
            uint32_t cmd = rd32(c), size = rd32(c + 4);
            if (size < 8) break;
            if (cmd == LC_SEGMENT_64 && size >= 72) {
                uint32_t nsects = rd32(c + 64);
                for (uint32_t s = 0; s < nsects && 72 + (uint64_t)(s + 1) * 80 <= size; s++) {
                    const unsigned char *sec = c + 72 + (size_t)s * 80;
                    char name[17];
                    copyName16(name, sec);
                    if (strcmp(name, "__cstring") && strcmp(name, "__objc_methname") && strcmp(name, "__objc_classname")) continue;
                    uint64_t size64 = rd64(sec + 40);
                    uint32_t off = rd32(sec + 48);
                    if (off == 0 || (uint64_t)off + size64 > imgSize) continue;
                    if (info->encrypted && off < cryptoff + cryptsize && (uint64_t)off + size64 > cryptoff) continue;
                    for (size_t k = 0; k < needleCount; k++) {
                        if (needleHits[k] < 255 && memmem(img + off, (size_t)size64, needles[k], strlen(needles[k]))) needleHits[k]++;
                    }
                }
            }
            p2 += size;
        }
    }

    munmap((void *)base, fileSize);
    info->valid = 1;
    return 0;
}

void RAEMachOFree(RAEMachOInfo *info) {
    for (size_t i = 0; i < info->libCount; i++) free(info->libs[i]);
    for (size_t i = 0; i < info->importCount; i++) free(info->imports[i]);
    for (size_t i = 0; i < info->classCount; i++) free(info->classes[i]);
    free(info->libs); free(info->imports); free(info->classes); free(info->sections);
    memset(info, 0, sizeof(*info));
}
