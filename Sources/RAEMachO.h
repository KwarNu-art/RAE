// Read-only Mach-O inspector (arm64). Plain C with its own struct layouts so it builds anywhere and can be tested.
#ifndef RAEMACHO_H
#define RAEMACHO_H

#include <stdint.h>
#include <stddef.h>

typedef struct {
    char segment[17];
    char section[17];
    uint64_t size;
} RAEMachOSection;

typedef struct {
    int valid;
    char error[128];
    uint32_t cputype, cpusubtype;
    int encrypted;                 // LC_ENCRYPTION_INFO(_64) with cryptid != 0
    uint32_t minOS;                // x.y.z packed as xxxxyyzz, 0 if unknown
    uint32_t sdk;
    char uuid[37];
    uint64_t fileSize;
    uint64_t functionCount;        // from LC_FUNCTION_STARTS
    uint64_t textSize, dataSize;   // __TEXT and __DATA segment sizes (vmsize)

    char **libs;     size_t libCount;        // linked dylibs and frameworks
    char **imports;  size_t importCount;     // undefined external symbols
    char **classes;  size_t classCount;      // ObjC classes defined by this binary (first 600 names)
    size_t classTotal;                        // total number of ObjC classes defined
    RAEMachOSection *sections; size_t sectionCount;
} RAEMachOInfo;

// Parse the file. `needles` are strings searched for inside the binary's string sections; needleHits[i] gets
// the number of sections in which needles[i] was found (0 if not found or the binary is encrypted).
// Returns 0 on success (info->valid == 1).
int RAEMachOParse(const char *path, RAEMachOInfo *info,
                  const char *const *needles, size_t needleCount, unsigned char *needleHits);
void RAEMachOFree(RAEMachOInfo *info);

#endif
