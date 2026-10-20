// Minimal read-only ZIP reader for IPA files (stored and deflate, ZIP64 aware). Plain C so it can be tested anywhere.
#ifndef RAEZIP_H
#define RAEZIP_H

#include <stdint.h>
#include <stdio.h>
#include <stddef.h>

typedef struct {
    char *name;
    uint64_t csize;
    uint64_t usize;
    uint64_t localOffset;
    uint16_t method;
} RAEZipEntry;

typedef struct {
    FILE *file;
    RAEZipEntry *entries;
    size_t count;
} RAEZip;

// Returns 0 on success, a negative number on failure.
int RAEZipOpen(RAEZip *zip, const char *path);
void RAEZipClose(RAEZip *zip);

// Index of the entry with exactly this name, or -1.
long RAEZipFind(const RAEZip *zip, const char *name);

// Extract to a file. Returns 0 on success. Fails if the entry is larger than maxBytes (0 = no limit).
int RAEZipExtractToFile(RAEZip *zip, size_t index, const char *outPath, uint64_t maxBytes);

// Extract to memory (caller frees). Returns NULL on failure or if larger than maxBytes.
unsigned char *RAEZipExtractToMemory(RAEZip *zip, size_t index, size_t *outLength, uint64_t maxBytes);

#endif
