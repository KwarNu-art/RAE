#include "../Sources/RAEZip.h"
#include "../Sources/RAEMachO.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures = 0;
#define CHECK(cond, msg) do { if (cond) printf("ok:   %s\n", msg); else { printf("FAIL: %s\n", msg); failures++; } } while (0)

static int has(char **list, size_t n, const char *s) { for (size_t i = 0; i < n; i++) if (!strcmp(list[i], s)) return 1; return 0; }

int main(int argc, char **argv) {
    RAEZip zip;
    CHECK(RAEZipOpen(&zip, argv[1]) == 0, "open ipa");
    CHECK(zip.count == 4, "four entries");
    long plist = RAEZipFind(&zip, "Payload/Example.app/Info.plist");
    CHECK(plist >= 0, "find Info.plist");
    size_t len = 0;
    unsigned char *data = RAEZipExtractToMemory(&zip, (size_t)plist, &len, 1 << 20);
    CHECK(data && len > 20 && memcmp(data, "bplist00", 8) == 0, "Info.plist extracted (deflate) and is a binary plist");
    free(data);
    long fw = RAEZipFind(&zip, "Payload/Example.app/Frameworks/UnityFramework.framework/UnityFramework");
    data = RAEZipExtractToMemory(&zip, (size_t)fw, &len, 1 << 20);
    CHECK(data && len == 5000 && data[0] == 'x', "stored entry extracted");
    free(data);
    CHECK(RAEZipExtractToMemory(&zip, (size_t)fw, &len, 100) == NULL, "size limit is enforced");

    long exe = RAEZipFind(&zip, "Payload/Example.app/Example");
    CHECK(RAEZipExtractToFile(&zip, (size_t)exe, "/tmp/rae_test_exe", 0) == 0, "extract executable to file");
    RAEZipClose(&zip);

    const char *needles[] = {"preferredFramesPerSecond", "CADisplayLink", "notpresent"};
    unsigned char hits[3];
    RAEMachOInfo info;
    CHECK(RAEMachOParse("/tmp/rae_test_exe", &info, needles, 3, hits) == 0 && info.valid, "parse Mach-O");
    CHECK(info.cputype == 0x0100000C, "arm64");
    CHECK(!info.encrypted, "not encrypted");
    CHECK(info.minOS == 0x000F0000, "min OS 15.0");
    CHECK(info.libCount == 1 && !strcmp(info.libs[0], "/System/Library/Frameworks/Metal.framework/Metal"), "linked library");
    CHECK(has(info.imports, info.importCount, "_OBJC_CLASS_$_CADisplayLink") && has(info.imports, info.importCount, "_MTLCreateSystemDefaultDevice"), "imports found");
    CHECK(info.importCount == 2, "defined symbol is not an import");
    CHECK(info.classTotal == 1 && info.classCount == 1 && !strcmp(info.classes[0], "MyGame"), "own ObjC class found");
    CHECK(hits[0] == 1 && hits[1] == 1 && hits[2] == 0, "string needles");
    CHECK(info.functionCount == 4, "function count from function starts");
    CHECK(!strcmp(info.uuid, "00010203-0405-0607-0809-0A0B0C0D0E0F"), "uuid");
    CHECK(info.sectionCount == 1 && !strcmp(info.sections[0].section, "__cstring"), "section list");
    RAEMachOFree(&info);

    if (argc > 2) {
        CHECK(RAEZipOpen(&zip, argv[2]) == 0, "open encrypted ipa");
        exe = RAEZipFind(&zip, "Payload/Example.app/Example");
        RAEZipExtractToFile(&zip, (size_t)exe, "/tmp/rae_test_exe2", 0);
        RAEZipClose(&zip);
        CHECK(RAEMachOParse("/tmp/rae_test_exe2", &info, needles, 3, hits) == 0 && info.encrypted, "encrypted flag detected");
        RAEMachOFree(&info);
    }

    CHECK(RAEZipOpen(&zip, "/tmp/rae_test_exe") != 0, "a non-zip is rejected");
    printf(failures ? "\nFAILED\n" : "\nall passed\n");
    return failures ? 1 : 0;
}
