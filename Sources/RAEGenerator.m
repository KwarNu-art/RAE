#import "RAEGenerator.h"

@implementation RAEGenerator

+ (NSString *)loadTemplate:(NSString *)name {
    NSString *base = NSBundle.mainBundle.bundlePath;
    for (NSString *path in @[[base stringByAppendingPathComponent:[@"templates" stringByAppendingPathComponent:name]],
                             [base stringByAppendingPathComponent:name]]) {
        NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
        if (text) return text;
    }
    return nil;
}

// Keeps only plain ASCII so nothing odd can end up in generated source or package fields.
+ (NSString *)plain:(NSString *)text fallback:(NSString *)fallback {
    NSMutableString *out = [NSMutableString string];
    for (NSUInteger i = 0; i < text.length && out.length < 60; i++) {
        unichar c = [text characterAtIndex:i];
        BOOL ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == ' ' || c == '-' || c == '.' || c == '_';
        [out appendString:ok ? [NSString stringWithFormat:@"%C", c] : @""];
    }
    NSString *trimmed = [out stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    return trimmed.length ? trimmed : fallback;
}

+ (BOOL)bundleIDIsSafe:(NSString *)s {
    if (!s.length || s.length > 200) return NO;
    NSCharacterSet *bad = [[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-_"] invertedSet];
    return [s rangeOfCharacterFromSet:bad].location == NSNotFound;
}

+ (NSString *)tweakNameForProject:(NSDictionary *)project {
    NSString *id_ = project[@"id"] ?: @"app";
    return [@"RAEBoost_" stringByAppendingString:[id_ stringByReplacingOccurrencesOfString:@"-" withString:@"_"]];
}

+ (NSString *)packageIDForProject:(NSDictionary *)project {
    NSString *bundle = [project[@"analysis"][@"bundleId"] lowercaseString] ?: @"app";
    bundle = [bundle stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
    return [@"com.rae.boost." stringByAppendingString:bundle];
}

+ (NSDictionary<NSString *, NSString *> *)substitutionsForProject:(NSDictionary *)project build:(NSInteger)build {
    NSDictionary *a = project[@"analysis"];
    NSDictionary *p = project[@"profile"];
    NSInteger mode = MAX(0, MIN(2, [p[@"frameMode"] integerValue]));
    BOOL mtk = [p[@"hookMTKView"] boolValue];
    NSString *appName = [self plain:a[@"appName"] fallback:@"App"];
    NSString *pkgName = [self plain:project[@"name"] fallback:[appName stringByAppendingString:@" Boost"]];
    NSString *(^onOff)(NSString *) = ^NSString *(NSString *k) { return [p[k] boolValue] ? @"1" : @"0"; };
    NSString *(^text)(NSString *) = ^NSString *(NSString *k) { return [p[k] boolValue] ? @"on" : @"off"; };
    NSArray *fpsText = @[@"left as the app wants (thermal guard only)", @"smooth: low requests are raised to the display maximum", @"cool: never above 60 fps"];
    NSString *graphics = [a[@"graphics"] count] ? [self plain:[a[@"graphics"] componentsJoinedByString:@", "] fallback:@"unknown"] : @"unknown";
    return @{
        @"APP_NAME": appName,
        @"PKGNAME": pkgName,
        @"BUNDLE_ID": a[@"bundleId"] ?: @"",
        @"TWEAK": [self tweakNameForProject:project],
        @"PACKAGE": [self packageIDForProject:project],
        @"BUILD": [NSString stringWithFormat:@"%ld", (long)build],
        @"DESC": [NSString stringWithFormat:@"Performance tweak for %@, made by RAE.", appName],
        @"EXTRA_FRAMEWORKS": mtk ? @" MetalKit" : @"",
        @"FPS_MODE": [NSString stringWithFormat:@"%ld", (long)mode],
        @"MEMORY_TRIM": onOff(@"memoryTrim"),
        @"TIMER_SAVING": onOff(@"timerSaving"),
        @"BACKGROUND_QUIET": onOff(@"backgroundQuiet"),
        @"THERMAL_GUARD": onOff(@"thermalGuard"),
        @"HOOK_MTKVIEW": mtk ? @"1" : @"0",
        @"FPS_TEXT": fpsText[mode],
        @"MEMORY_TEXT": text(@"memoryTrim"),
        @"TIMER_TEXT": text(@"timerSaving"),
        @"BACKGROUND_TEXT": text(@"backgroundQuiet"),
        @"THERMAL_TEXT": text(@"thermalGuard"),
        @"ENGINE": [self plain:a[@"engine"] fallback:@"unknown"],
        @"GRAPHICS": graphics,
    };
}

+ (NSString *)fill:(NSString *)template with:(NSDictionary<NSString *, NSString *> *)values {
    NSMutableString *out = [template mutableCopy];
    [values enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        [out replaceOccurrencesOfString:[NSString stringWithFormat:@"{{%@}}", key] withString:value options:0 range:NSMakeRange(0, out.length)];
    }];
    return out;
}

+ (NSDictionary<NSString *, NSData *> *)projectFilesForProject:(NSDictionary *)project build:(NSInteger)build error:(NSError **)error {
    NSString *bundleID = project[@"analysis"][@"bundleId"];
    if (![self bundleIDIsSafe:bundleID]) {
        if (error) *error = [NSError errorWithDomain:@"RAE" code:2 userInfo:@{NSLocalizedDescriptionKey: @"This app's bundle id has unusual characters, so RAE will not generate code for it."}];
        return nil;
    }
    NSDictionary *values = [self substitutionsForProject:project build:build];
    NSString *folder = [@"projects" stringByAppendingPathComponent:project[@"id"]];
    NSDictionary *map = @{
        @"Tweak.x": @"Tweak.x.tpl",
        @"Makefile": @"Makefile.tpl",
        @"control": @"control.tpl",
        @"Config.h": @"Config.h.tpl",
        @"README.md": @"Project-README.md.tpl",
        [NSString stringWithFormat:@"%@.plist", values[@"TWEAK"]]: @"Filter.plist.tpl",
    };
    NSMutableDictionary *files = [NSMutableDictionary dictionary];
    for (NSString *target in map) {
        NSString *template = [self loadTemplate:map[target]];
        if (!template) {
            if (error) *error = [NSError errorWithDomain:@"RAE" code:3 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Template %@ is missing from the app.", map[target]]}];
            return nil;
        }
        files[[folder stringByAppendingPathComponent:target]] = [[self fill:template with:values] dataUsingEncoding:NSUTF8StringEncoding];
    }
    return files;
}

+ (NSData *)workflowFile {
    NSString *text = [self loadTemplate:@"build.yml.tpl"];
    return [text dataUsingEncoding:NSUTF8StringEncoding];
}

+ (NSString *)tweakSourcePreviewForProject:(NSDictionary *)project {
    NSDictionary *values = [self substitutionsForProject:project build:1];
    NSString *config = [self fill:[self loadTemplate:@"Config.h.tpl"] ?: @"" with:values];
    NSString *tweak = [self fill:[self loadTemplate:@"Tweak.x.tpl"] ?: @"" with:values];
    return [NSString stringWithFormat:@"// Config.h\n%@\n\n// Tweak.x\n%@", config, tweak];
}

@end
