#include "RAEZip.h"
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

#define RAE_ZIP_CHUNK 65536

static uint16_t rd16(const unsigned char *p) { return (uint16_t)(p[0] | (p[1] << 8)); }
static uint32_t rd32(const unsigned char *p) { return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24); }
static uint64_t rd64(const unsigned char *p) { return (uint64_t)rd32(p) | ((uint64_t)rd32(p + 4) << 32); }

static int seek64(FILE *f, uint64_t off) { return fseeko(f, (off_t)off, SEEK_SET); }

int RAEZipOpen(RAEZip *zip, const char *path) {
    memset(zip, 0, sizeof(*zip));
    zip->file = fopen(path, "rb");
    if (!zip->file) return -1;

    if (fseeko(zip->file, 0, SEEK_END) != 0) { RAEZipClose(zip); return -2; }
    uint64_t size = (uint64_t)ftello(zip->file);
    if (size < 22) { RAEZipClose(zip); return -3; }

    // Find the end of central directory record, searching back through a possible comment.
    uint64_t span = size < 65557 ? size : 65557;
    unsigned char *tail = malloc((size_t)span);
    if (!tail) { RAEZipClose(zip); return -4; }
    seek64(zip->file, size - span);
    if (fread(tail, 1, (size_t)span, zip->file) != span) { free(tail); RAEZipClose(zip); return -5; }
    long eocd = -1;
    for (long i = (long)span - 22; i >= 0; i--) {
        if (tail[i] == 0x50 && tail[i + 1] == 0x4b && tail[i + 2] == 0x05 && tail[i + 3] == 0x06) { eocd = i; break; }
    }
    if (eocd < 0) { free(tail); RAEZipClose(zip); return -6; }

    uint64_t total = rd16(tail + eocd + 10);
    uint64_t cdSize = rd32(tail + eocd + 12);
    uint64_t cdOffset = rd32(tail + eocd + 16);
    uint64_t eocdAbs = size - span + (uint64_t)eocd;

    if ((total == 0xFFFF || cdSize == 0xFFFFFFFFu || cdOffset == 0xFFFFFFFFu) && eocdAbs >= 20) {
        unsigned char loc[20];
        seek64(zip->file, eocdAbs - 20);
        if (fread(loc, 1, 20, zip->file) == 20 && rd32(loc) == 0x07064b50) {
            unsigned char z64[56];
            seek64(zip->file, rd64(loc + 8));
            if (fread(z64, 1, 56, zip->file) == 56 && rd32(z64) == 0x06064b50) {
                total = rd64(z64 + 32);
                cdSize = rd64(z64 + 40);
                cdOffset = rd64(z64 + 48);
            }
        }
    }
    free(tail);

    if (cdSize == 0 || cdSize > (uint64_t)1 << 30) { RAEZipClose(zip); return -7; }
    unsigned char *cd = malloc((size_t)cdSize);
    if (!cd) { RAEZipClose(zip); return -8; }
    seek64(zip->file, cdOffset);
    if (fread(cd, 1, (size_t)cdSize, zip->file) != cdSize) { free(cd); RAEZipClose(zip); return -9; }

    zip->entries = calloc((size_t)total + 1, sizeof(RAEZipEntry));
    if (!zip->entries) { free(cd); RAEZipClose(zip); return -10; }

    uint64_t pos = 0;
    size_t n = 0;
    while (n < total && pos + 46 <= cdSize && rd32(cd + pos) == 0x02014b50) {
        uint16_t method = rd16(cd + pos + 10);
        uint64_t csize = rd32(cd + pos + 20);
        uint64_t usize = rd32(cd + pos + 24);
        uint16_t nameLen = rd16(cd + pos + 28);
        uint16_t extraLen = rd16(cd + pos + 30);
        uint16_t commentLen = rd16(cd + pos + 32);
        uint64_t lho = rd32(cd + pos + 42);
        if (pos + 46 + nameLen + extraLen + commentLen > cdSize) break;

        // ZIP64 extra field holds the real values for any field that is 0xFFFFFFFF, in this order.
        const unsigned char *extra = cd + pos + 46 + nameLen;
        uint32_t e = 0;
        while (e + 4 <= extraLen) {
            uint16_t id = rd16(extra + e), len = rd16(extra + e + 2);
            if (e + 4 + len > extraLen) break;
            if (id == 0x0001) {
                uint32_t q = e + 4;
                if (usize == 0xFFFFFFFFu && q + 8 <= e + 4 + len) { usize = rd64(extra + q); q += 8; }
                if (csize == 0xFFFFFFFFu && q + 8 <= e + 4 + len) { csize = rd64(extra + q); q += 8; }
                if (lho == 0xFFFFFFFFu && q + 8 <= e + 4 + len) { lho = rd64(extra + q); q += 8; }
            }
            e += 4 + len;
        }

        char *name = malloc((size_t)nameLen + 1);
        if (!name) break;
        memcpy(name, cd + pos + 46, nameLen);
        name[nameLen] = 0;
        zip->entries[n].name = name;
        zip->entries[n].csize = csize;
        zip->entries[n].usize = usize;
        zip->entries[n].localOffset = lho;
        zip->entries[n].method = method;
        n++;
        pos += 46 + (uint64_t)nameLen + extraLen + commentLen;
    }
    zip->count = n;
    free(cd);
    return n > 0 ? 0 : -11;
}

void RAEZipClose(RAEZip *zip) {
    if (zip->entries) {
        for (size_t i = 0; i < zip->count; i++) free(zip->entries[i].name);
        free(zip->entries);
    }
    if (zip->file) fclose(zip->file);
    memset(zip, 0, sizeof(*zip));
}

long RAEZipFind(const RAEZip *zip, const char *name) {
    for (size_t i = 0; i < zip->count; i++) {
        if (strcmp(zip->entries[i].name, name) == 0) return (long)i;
    }
    return -1;
}

// Position the file at the start of the entry's data.
static int seekToData(RAEZip *zip, const RAEZipEntry *entry) {
    unsigned char h[30];
    if (seek64(zip->file, entry->localOffset) != 0) return -1;
    if (fread(h, 1, 30, zip->file) != 30 || rd32(h) != 0x04034b50) return -1;
    uint64_t dataStart = entry->localOffset + 30 + rd16(h + 26) + rd16(h + 28);
    return seek64(zip->file, dataStart);
}

// Streams the entry through `sink`. Returns 0 on success.
static int streamEntry(RAEZip *zip, size_t index, uint64_t maxBytes,
                       int (*sink)(const unsigned char *, size_t, void *), void *ctx) {
    if (index >= zip->count) return -1;
    const RAEZipEntry *entry = &zip->entries[index];
    if (maxBytes && entry->usize > maxBytes) return -2;
    if (entry->method != 0 && entry->method != 8) return -3;
    if (seekToData(zip, entry) != 0) return -4;

    unsigned char in[RAE_ZIP_CHUNK], out[RAE_ZIP_CHUNK];
    uint64_t remaining = entry->csize;

    if (entry->method == 0) {
        while (remaining) {
            size_t want = remaining < RAE_ZIP_CHUNK ? (size_t)remaining : RAE_ZIP_CHUNK;
            if (fread(in, 1, want, zip->file) != want) return -5;
            if (sink(in, want, ctx) != 0) return -6;
            remaining -= want;
        }
        return 0;
    }

    z_stream z;
    memset(&z, 0, sizeof(z));
    if (inflateInit2(&z, -MAX_WBITS) != Z_OK) return -7;
    int status = Z_OK, result = 0;
    while (status != Z_STREAM_END) {
        if (z.avail_in == 0) {
            size_t want = remaining < RAE_ZIP_CHUNK ? (size_t)remaining : RAE_ZIP_CHUNK;
            if (want == 0) { result = -8; break; }
            if (fread(in, 1, want, zip->file) != want) { result = -5; break; }
            remaining -= want;
            z.next_in = in;
            z.avail_in = (uInt)want;
        }
        z.next_out = out;
        z.avail_out = RAE_ZIP_CHUNK;
        status = inflate(&z, Z_NO_FLUSH);
        if (status != Z_OK && status != Z_STREAM_END) { result = -9; break; }
        size_t produced = RAE_ZIP_CHUNK - z.avail_out;
        if (produced && sink(out, produced, ctx) != 0) { result = -6; break; }
    }
    inflateEnd(&z);
    return result;
}

static int fileSink(const unsigned char *data, size_t len, void *ctx) {
    return fwrite(data, 1, len, (FILE *)ctx) == len ? 0 : -1;
}

int RAEZipExtractToFile(RAEZip *zip, size_t index, const char *outPath, uint64_t maxBytes) {
    FILE *out = fopen(outPath, "wb");
    if (!out) return -10;
    int r = streamEntry(zip, index, maxBytes, fileSink, out);
    fclose(out);
    if (r != 0) remove(outPath);
    return r;
}

typedef struct { unsigned char *data; size_t len, cap; } MemBuf;

static int memSink(const unsigned char *data, size_t len, void *ctx) {
    MemBuf *b = ctx;
    if (b->len + len + 1 > b->cap) {
        size_t cap = b->cap ? b->cap : 4096;
        while (cap < b->len + len + 1) cap *= 2;
        unsigned char *p = realloc(b->data, cap);
        if (!p) return -1;
        b->data = p;
        b->cap = cap;
    }
    memcpy(b->data + b->len, data, len);
    b->len += len;
    return 0;
}

unsigned char *RAEZipExtractToMemory(RAEZip *zip, size_t index, size_t *outLength, uint64_t maxBytes) {
    MemBuf b = {0};
    if (streamEntry(zip, index, maxBytes, memSink, &b) != 0) { free(b.data); return NULL; }
    if (!b.data) { b.data = malloc(1); if (!b.data) return NULL; }
    b.data[b.len] = 0;
    if (outLength) *outLength = b.len;
    return b.data;
}
