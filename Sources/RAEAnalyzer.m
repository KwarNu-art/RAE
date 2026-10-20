#import "RAEAnalyzer.h"
#import "RAEZip.h"
#import "RAEMachO.h"

static NSError *RAEError(NSString *message) {
    return [NSError errorWithDomain:@"RAE" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSString *RAEVersionString(uint32_t packed) {
    if (!packed) return @"unknown";
    return [NSString stringWithFormat:@"%u.%u", packed >> 16, (packed >> 8) & 0xff];
}

static BOOL RAEContains(NSString *haystack, NSString *needle) {
    return [haystack rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound;
}

// Needles searched for inside the binary's strings: frame pacing, timers, memory handling and engines.
static const char *const kNeedles[] = {
    "preferredFramesPerSecond",          // 0
    "preferredFrameRateRange",           // 1
    "CADisplayLink",                     // 2
    "MTKView",                           // 3
    "CAMetalLayer",                      // 4
    "didReceiveMemoryWarning",           // 5
    "scheduledTimerWithTimeInterval",    // 6
    "NSURLSession",                      // 7
    "WKWebView",                         // 8
    "UnityAppController",                // 9
    "il2cpp",                            // 10
    "cocos2d",                           // 11
    "UnrealEngine",                      // 12
    "AVAudioSession",                    // 13
    "CLLocationManager",                 // 14
    "setFrameInterval",                  // 15
};
enum { kNeedleCount = sizeof(kNeedles) / sizeof(kNeedles[0]) };

@implementation RAEAnalyzer

+ (NSDictionary *)analyzeIPAAtPath:(NSString *)ipaPath progress:(void (^)(NSString *))progress error:(NSError **)error {
    void (^step)(NSString *) = ^(NSString *s) { if (progress) progress(s); };

    step(@"Opening the IPA…");
    RAEZip zip;
    if (RAEZipOpen(&zip, ipaPath.fileSystemRepresentation) != 0) {
        if (error) *error = RAEError(@"This file is not a readable IPA (it is not a valid zip archive).");
        return nil;
    }

    // Find Payload/<Name>.app/Info.plist
    NSString *appDir = nil;
    long plistIndex = -1;
    for (size_t i = 0; i < zip.count; i++) {
        NSString *name = [NSString stringWithUTF8String:zip.entries[i].name] ?: @"";
        if (![name hasPrefix:@"Payload/"] || ![name hasSuffix:@".app/Info.plist"]) continue;
        if ([name componentsSeparatedByString:@"/"].count != 3) continue;
        appDir = [name stringByDeletingLastPathComponent];
        plistIndex = (long)i;
        break;
    }
    if (plistIndex < 0) {
        RAEZipClose(&zip);
        if (error) *error = RAEError(@"No app found inside this IPA (Payload/<name>.app is missing).");
        return nil;
    }

    size_t plistLen = 0;
    unsigned char *plistBytes = RAEZipExtractToMemory(&zip, (size_t)plistIndex, &plistLen, 8 << 20);
    NSDictionary *info = nil;
    if (plistBytes) {
        NSData *data = [NSData dataWithBytesNoCopy:plistBytes length:plistLen freeWhenDone:YES];
        id obj = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
        if ([obj isKindOfClass:NSDictionary.class]) info = obj;
    }
    if (!info) {
        RAEZipClose(&zip);
        if (error) *error = RAEError(@"The app's Info.plist could not be read.");
        return nil;
    }

    // Walk every entry once: sizes by category, embedded frameworks, extensions.
    step(@"Reading the file list…");
    NSMutableDictionary<NSString *, NSNumber *> *category = [NSMutableDictionary dictionary];
    NSMutableOrderedSet<NSString *> *embedded = [NSMutableOrderedSet orderedSet];
    NSMutableOrderedSet<NSString *> *plugins = [NSMutableOrderedSet orderedSet];
    NSMutableString *allPaths = [NSMutableString string];
    uint64_t totalBytes = 0;
    NSString *frameworksPrefix = [appDir stringByAppendingString:@"/Frameworks/"];
    NSString *pluginsPrefix = [appDir stringByAppendingString:@"/PlugIns/"];
    NSDictionary<NSString *, NSString *> *extMap = @{
        @"png": @"Images", @"jpg": @"Images", @"jpeg": @"Images", @"webp": @"Images", @"heic": @"Images",
        @"astc": @"Textures", @"ktx": @"Textures", @"pvr": @"Textures", @"dds": @"Textures", @"tga": @"Textures",
        @"mp3": @"Audio", @"m4a": @"Audio", @"caf": @"Audio", @"wav": @"Audio", @"ogg": @"Audio",
        @"aac": @"Audio", @"bank": @"Audio", @"mp4": @"Video", @"mov": @"Video", @"m4v": @"Video",
        @"unity3d": @"Game data", @"assetbundle": @"Game data", @"pak": @"Game data", @"obb": @"Game data",
        @"bundle": @"Game data", @"bin": @"Game data", @"dat": @"Game data", @"json": @"Config and text",
        @"plist": @"Config and text", @"strings": @"Config and text", @"xml": @"Config and text",
        @"nib": @"Interface", @"storyboardc": @"Interface", @"car": @"Interface",
        @"dylib": @"Code libraries", @"ttf": @"Fonts", @"otf": @"Fonts",
    };
    for (size_t i = 0; i < zip.count; i++) {
        const RAEZipEntry *e = &zip.entries[i];
        NSString *name = [NSString stringWithUTF8String:e->name];
        if (!name || ![name hasPrefix:appDir]) continue;
        totalBytes += e->usize;
        if (allPaths.length < 400000) { [allPaths appendString:name]; [allPaths appendString:@"\n"]; }
        if ([name hasPrefix:frameworksPrefix]) {
            NSString *rest = [name substringFromIndex:frameworksPrefix.length];
            NSString *first = [rest componentsSeparatedByString:@"/"].firstObject;
            if (first.length) [embedded addObject:first];
        }
        if ([name hasPrefix:pluginsPrefix]) {
            NSString *first = [[name substringFromIndex:pluginsPrefix.length] componentsSeparatedByString:@"/"].firstObject;
            if (first.length) [plugins addObject:first];
        }
        NSString *group = extMap[name.pathExtension.lowercaseString] ?: @"Other";
        if ([name hasSuffix:@"/"]) continue;
        category[group] = @(category[group].unsignedLongLongValue + e->usize);
    }

    // The main executable.
    NSString *exeName = info[@"CFBundleExecutable"];
    if (![exeName isKindOfClass:NSString.class] || !exeName.length) exeName = [[appDir lastPathComponent] stringByDeletingPathExtension];
    long exeIndex = RAEZipFind(&zip, [[appDir stringByAppendingPathComponent:exeName] UTF8String]);
    if (exeIndex < 0) {
        RAEZipClose(&zip);
        if (error) *error = RAEError(@"The app's main executable is missing from the IPA.");
        return nil;
    }
    step(@"Extracting the main executable…");
    NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"rae-%@.bin", NSUUID.UUID.UUIDString]];
    int rc = RAEZipExtractToFile(&zip, (size_t)exeIndex, tmp.fileSystemRepresentation, (uint64_t)1500 << 20);
    RAEZipClose(&zip);
    if (rc != 0) {
        if (error) *error = RAEError(rc == -2 ? @"The main executable is larger than 1.5 GB, which RAE cannot read on a phone." : @"The main executable could not be extracted.");
        return nil;
    }

    step(@"Inspecting the binary…");
    RAEMachOInfo mo;
    unsigned char hits[kNeedleCount];
    RAEMachOParse(tmp.fileSystemRepresentation, &mo, kNeedles, kNeedleCount, hits);
    [NSFileManager.defaultManager removeItemAtPath:tmp error:NULL];
    if (!mo.valid) {
        NSString *msg = [NSString stringWithFormat:@"The executable could not be read: %s", mo.error];
        RAEMachOFree(&mo);
        if (error) *error = RAEError(msg);
        return nil;
    }

    step(@"Building the report…");
    NSMutableArray *libs = [NSMutableArray array];
    for (size_t i = 0; i < mo.libCount; i++) {
        NSString *lib = [NSString stringWithUTF8String:mo.libs[i]] ?: @"";
        [libs addObject:[lib.lastPathComponent copy]];
    }
    NSMutableSet *importSet = [NSMutableSet set];
    for (size_t i = 0; i < mo.importCount; i++) {
        NSString *s = [NSString stringWithUTF8String:mo.imports[i]];
        if (s) [importSet addObject:s];
    }
    NSMutableArray *classes = [NSMutableArray array];
    for (size_t i = 0; i < mo.classCount; i++) {
        NSString *s = [NSString stringWithUTF8String:mo.classes[i]];
        if (s) [classes addObject:s];
    }
    NSString *libsJoined = [libs componentsJoinedByString:@" "];
    NSString *embeddedJoined = [embedded.array componentsJoinedByString:@" "];
    NSString *classesJoined = [classes componentsJoinedByString:@" "];

    BOOL (^hasImport)(NSString *) = ^BOOL(NSString *s) { return [importSet containsObject:s]; };
#define needle(i) (hits[(i)] > 0)

    BOOL usesDisplayLink = hasImport(@"_OBJC_CLASS_$_CADisplayLink") || needle(2);
    BOOL usesMTKView = hasImport(@"_OBJC_CLASS_$_MTKView") || needle(3);
    BOOL usesMetal = hasImport(@"_MTLCreateSystemDefaultDevice") || RAEContains(libsJoined, @"Metal") || needle(4);
    BOOL usesGLES = RAEContains(libsJoined, @"OpenGLES") || hasImport(@"_glDrawArrays");
    BOOL usesVulkan = RAEContains(embeddedJoined, @"MoltenVK") || RAEContains(libsJoined, @"MoltenVK");

    // Engine
    NSString *engine = @"Native (UIKit / SwiftUI)";
    if (RAEContains(allPaths, @"UnityFramework") || RAEContains(allPaths, @"Data/Managed") || needle(9) || needle(10) || RAEContains(classesJoined, @"UnityAppController")) engine = @"Unity";
    else if (RAEContains(allPaths, @"unrealengine") || RAEContains(allPaths, @"ue4commandline") || RAEContains(allPaths, @"/cookeddata/") || needle(12)) engine = @"Unreal Engine";
    else if (RAEContains(allPaths, @"cocos") || needle(11)) engine = @"Cocos2d / Cocos Creator";
    else if (RAEContains(allPaths, @"godot")) engine = @"Godot";
    else if (RAEContains(embeddedJoined, @"Flutter")) engine = @"Flutter";
    else if (RAEContains(allPaths, @"main.jsbundle") || RAEContains(embeddedJoined, @"hermes") || RAEContains(embeddedJoined, @"React.framework")) engine = @"React Native";
    else if (RAEContains(embeddedJoined, @"Xamarin") || RAEContains(allPaths, @"Xamarin.")) engine = @"Xamarin / .NET";
    else if (RAEContains(libsJoined, @"SwiftUI")) engine = @"Native (SwiftUI)";

    NSMutableArray *graphics = [NSMutableArray array];
    if (usesMetal) [graphics addObject:@"Metal"];
    if (usesGLES) [graphics addObject:@"OpenGL ES"];
    if (usesVulkan) [graphics addObject:@"Vulkan (MoltenVK)"];
    if (usesMTKView) [graphics addObject:@"MTKView render loop"];

    NSMutableArray *frameSignals = [NSMutableArray array];
    if (usesDisplayLink) [frameSignals addObject:@"CADisplayLink (the app drives its own frame loop)"];
    if (needle(0)) [frameSignals addObject:@"sets preferredFramesPerSecond"];
    if (needle(1)) [frameSignals addObject:@"uses preferredFrameRateRange (iOS 15 frame rate control)"];
    if (needle(15)) [frameSignals addObject:@"uses the old frameInterval API"];
    if (info[@"CADisableMinimumFrameDurationOnPhone"]) [frameSignals addObject:@"Info.plist enables 120 Hz on ProMotion iPhones (CADisableMinimumFrameDurationOnPhone)"];

    // SDKs that wake the app in the background (ads, analytics, attribution, crash reporting).
    NSDictionary<NSString *, NSString *> *sdkMap = @{
        @"firebase": @"Firebase", @"appsflyer": @"AppsFlyer", @"adjust": @"Adjust", @"fbsdk": @"Facebook SDK",
        @"facebook": @"Facebook SDK", @"crashlytics": @"Crashlytics", @"googlemobileads": @"Google Mobile Ads",
        @"admob": @"AdMob", @"unityads": @"Unity Ads", @"applovin": @"AppLovin", @"ironsource": @"ironSource",
        @"vungle": @"Vungle", @"chartboost": @"Chartboost", @"mopub": @"MoPub", @"flurry": @"Flurry",
        @"amplitude": @"Amplitude", @"mixpanel": @"Mixpanel", @"sentry": @"Sentry", @"bugly": @"Bugly",
        @"umeng": @"Umeng", @"onesignal": @"OneSignal", @"branch": @"Branch", @"agora": @"Agora (voice/video)",
        @"webrtc": @"WebRTC", @"lottie": @"Lottie animations",
    };
    NSString *sdkHaystack = [NSString stringWithFormat:@"%@ %@ %@", embeddedJoined, libsJoined, classesJoined];
    NSMutableOrderedSet *sdks = [NSMutableOrderedSet orderedSet];
    for (NSString *key in [sdkMap.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        if (RAEContains(sdkHaystack, key)) [sdks addObject:sdkMap[key]];
    }
    NSMutableArray *adsAndTracking = [NSMutableArray array];
    for (NSString *s in sdks) if (![s hasPrefix:@"Lottie"] && ![s hasPrefix:@"Agora"] && ![s hasPrefix:@"WebRTC"]) [adsAndTracking addObject:s];

    NSArray *bgModes = [info[@"UIBackgroundModes"] isKindOfClass:NSArray.class] ? info[@"UIBackgroundModes"] : @[];
    NSMutableArray *permissions = [NSMutableArray array];
    for (NSString *key in [info.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        if ([key hasSuffix:@"UsageDescription"]) [permissions addObject:[key stringByReplacingOccurrencesOfString:@"UsageDescription" withString:@""]];
    }

    NSMutableDictionary *sizes = [NSMutableDictionary dictionary];
    for (NSString *k in category) sizes[k] = @(round(category[k].doubleValue / 1048576.0 * 10) / 10);

    // Interesting imports for the report.
    NSArray *prefixes = @[@"_OBJC_CLASS_$_CA", @"_OBJC_CLASS_$_MTL", @"_OBJC_CLASS_$_MTK", @"_OBJC_CLASS_$_AV",
                          @"_OBJC_CLASS_$_CL", @"_OBJC_CLASS_$_NSURLSession", @"_OBJC_CLASS_$_WK", @"_OBJC_CLASS_$_SK",
                          @"_OBJC_CLASS_$_GK", @"_OBJC_CLASS_$_UIApplication", @"_OBJC_CLASS_$_NSTimer",
                          @"_dispatch_", @"_pthread_create", @"_mach_", @"_os_proc", @"_sysctl", @"_MTL", @"_gl", @"_vk"];
    NSMutableArray *notable = [NSMutableArray array];
    for (NSString *imp in [[importSet allObjects] sortedArrayUsingSelector:@selector(compare:)]) {
        for (NSString *p in prefixes) {
            if ([imp hasPrefix:p]) { [notable addObject:imp]; break; }
        }
        if (notable.count >= 90) break;
    }

    // Levers: what a performance dylib could safely change for this app.
    BOOL frameLoop = usesDisplayLink || usesMTKView || needle(0) || needle(1);
    BOOL keepRunning = NO;
    for (NSString *mode in bgModes) {
        if ([@[@"audio", @"voip", @"location", @"bluetooth-central", @"bluetooth-peripheral", @"external-accessory"] containsObject:mode]) keepRunning = YES;
    }
    NSMutableArray *findings = [NSMutableArray array];
    NSMutableArray *warnings = [NSMutableArray array];
    if (mo.encrypted) [warnings addObject:@"This binary is still encrypted (FairPlay). Only the headers could be read; strings and code are hidden. Decrypt it first (RAE does not decrypt)."];
    if (frameLoop) [findings addObject:@"The app runs its own frame loop, so frame pacing can be controlled safely (frame rate control)."];
    else [findings addObject:@"No custom frame loop found: it likely uses standard UIKit/SwiftUI, which already follows the display rate."];
    double textureMB = [sizes[@"Textures"] doubleValue] + [sizes[@"Images"] doubleValue] + [sizes[@"Game data"] doubleValue];
    if (textureMB > 250) [findings addObject:[NSString stringWithFormat:@"About %.0f MB of textures, images and game data: high memory use is likely, so memory trimming helps.", textureMB]];
    if (adsAndTracking.count >= 3) [findings addObject:[NSString stringWithFormat:@"%lu ads/analytics SDKs (%@): they wake the app and the network often, which costs battery and heat.", (unsigned long)adsAndTracking.count, [[adsAndTracking subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)4, adsAndTracking.count))] componentsJoinedByString:@", "]]];
    if (keepRunning) [findings addObject:@"Declares background audio, VoIP, location or Bluetooth use, so background throttling is switched off to avoid breaking it."];
    if ([engine isEqualToString:@"Unity"] || [engine isEqualToString:@"Unreal Engine"] || [engine isEqualToString:@"Cocos2d / Cocos Creator"]) [findings addObject:[NSString stringWithFormat:@"Game engine: %@. Heat mostly comes from the frame rate and GPU load, so frame control and the thermal guard matter most.", engine]];
    if (mo.minOS && mo.minOS < (14u << 16)) [findings addObject:[NSString stringWithFormat:@"Built for iOS %@ and later: older code paths can be slower on current iOS.", RAEVersionString(mo.minOS)]];

    NSDictionary *profile = @{
        @"frameMode": frameLoop ? @1 : @0,        // 0 = leave as the app wants, 1 = smooth, 2 = cool
        @"memoryTrim": @YES,
        @"timerSaving": @YES,
        @"backgroundQuiet": @(!keepRunning),
        @"thermalGuard": @YES,
        @"hookMTKView": @(usesMTKView),
    };

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"appName"] = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: exeName;
    result[@"bundleId"] = info[@"CFBundleIdentifier"] ?: @"unknown";
    result[@"version"] = info[@"CFBundleShortVersionString"] ?: @"?";
    result[@"build"] = info[@"CFBundleVersion"] ?: @"?";
    result[@"minOS"] = info[@"MinimumOSVersion"] ?: RAEVersionString(mo.minOS);
    result[@"executable"] = exeName;
    result[@"binaryMB"] = @(round(mo.fileSize / 1048576.0 * 10) / 10);
    result[@"totalMB"] = @(round(totalBytes / 1048576.0 * 10) / 10);
    result[@"textMB"] = @(round(mo.textSize / 1048576.0 * 10) / 10);
    result[@"dataMB"] = @(round(mo.dataSize / 1048576.0 * 10) / 10);
    result[@"encrypted"] = @(mo.encrypted != 0);
    result[@"uuid"] = [NSString stringWithUTF8String:mo.uuid] ?: @"";
    result[@"functionCount"] = @(mo.functionCount);
    result[@"classTotal"] = @(mo.classTotal);
    result[@"classSample"] = [classes subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)80, classes.count))];
    result[@"engine"] = engine;
    result[@"graphics"] = graphics;
    result[@"frameSignals"] = frameSignals;
    result[@"linkedLibs"] = libs;
    result[@"embeddedFrameworks"] = embedded.array;
    result[@"extensions"] = plugins.array;
    result[@"sdks"] = sdks.array;
    result[@"backgroundModes"] = bgModes;
    result[@"permissions"] = permissions;
    result[@"sizesMB"] = sizes;
    result[@"notableImports"] = notable;
    result[@"findings"] = findings;
    result[@"warnings"] = warnings;
    result[@"profile"] = profile;
    result[@"analyzedAt"] = @([NSDate date].timeIntervalSince1970);
    RAEMachOFree(&mo);
    return result;
}

+ (NSString *)factsReportForAnalysis:(NSDictionary *)a {
    NSMutableString *s = [NSMutableString string];
    NSString *(^list)(NSArray *, NSUInteger) = ^NSString *(NSArray *arr, NSUInteger max) {
        if (!arr.count) return @"none";
        NSArray *head = [arr subarrayWithRange:NSMakeRange(0, MIN(max, arr.count))];
        NSString *joined = [head componentsJoinedByString:@", "];
        return arr.count > max ? [joined stringByAppendingFormat:@" … (+%lu more)", (unsigned long)(arr.count - max)] : joined;
    };
    [s appendFormat:@"%@  %@ (build %@)\n%@\n\n", a[@"appName"], a[@"version"], a[@"build"], a[@"bundleId"]];
    for (NSString *w in a[@"warnings"]) [s appendFormat:@"⚠️ %@\n\n", w];
    [s appendFormat:@"BINARY\n• Architecture: arm64, minimum iOS %@\n• Main executable: %@ MB (code %@ MB, data %@ MB)\n• Whole app: %@ MB\n• Functions: %@   ObjC classes: %@\n• Encrypted: %@\n• UUID: %@\n\n",
        a[@"minOS"], a[@"binaryMB"], a[@"textMB"], a[@"dataMB"], a[@"totalMB"], a[@"functionCount"], a[@"classTotal"],
        [a[@"encrypted"] boolValue] ? @"yes" : @"no", a[@"uuid"]];
    [s appendFormat:@"ENGINE AND GRAPHICS\n• Engine: %@\n• Graphics: %@\n• Frame pacing: %@\n\n", a[@"engine"], list(a[@"graphics"], 8), list(a[@"frameSignals"], 8)];
    [s appendFormat:@"BACKGROUND AND SDKs\n• Background modes: %@\n• SDKs: %@\n• App extensions: %@\n• Permissions asked: %@\n\n",
        list(a[@"backgroundModes"], 10), list(a[@"sdks"], 20), list(a[@"extensions"], 10), list(a[@"permissions"], 15)];
    NSDictionary *sizes = a[@"sizesMB"];
    NSArray *keys = [sizes.allKeys sortedArrayUsingComparator:^NSComparisonResult(id x, id y) { return [sizes[y] compare:sizes[x]]; }];
    [s appendString:@"SIZE BY TYPE (uncompressed)\n"];
    for (NSString *k in keys) [s appendFormat:@"• %@: %@ MB\n", k, sizes[k]];
    [s appendFormat:@"\nEMBEDDED FRAMEWORKS (%lu)\n%@\n\n", (unsigned long)[a[@"embeddedFrameworks"] count], list(a[@"embeddedFrameworks"], 40)];
    [s appendFormat:@"LINKED LIBRARIES (%lu)\n%@\n\n", (unsigned long)[a[@"linkedLibs"] count], list(a[@"linkedLibs"], 40)];
    [s appendFormat:@"OWN CLASSES (sample)\n%@\n\n", list(a[@"classSample"], 40)];
    [s appendFormat:@"NOTABLE SYSTEM CALLS\n%@\n\n", list(a[@"notableImports"], 40)];
    [s appendString:@"WHAT THIS MEANS\n"];
    for (NSString *f in a[@"findings"]) [s appendFormat:@"• %@\n", f];
    NSDictionary *p = a[@"profile"];
    NSArray *modes = @[@"leave as the app wants", @"smooth (raise low requests to the display maximum)", @"cool (never above 60 fps)"];
    [s appendFormat:@"\nSUGGESTED BOOST PROFILE\n• Frame rate: %@\n• Memory trim: %@\n• Timer saving: %@\n• Background quiet: %@\n• Thermal guard: %@\n",
        modes[MIN((NSUInteger)2, [p[@"frameMode"] unsignedIntegerValue])],
        [p[@"memoryTrim"] boolValue] ? @"on" : @"off", [p[@"timerSaving"] boolValue] ? @"on" : @"off",
        [p[@"backgroundQuiet"] boolValue] ? @"on" : @"off", [p[@"thermalGuard"] boolValue] ? @"on" : @"off"];
    return s;
}

@end
