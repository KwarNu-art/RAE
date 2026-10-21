#import "RAEStore.h"

@implementation RAEStore {
    NSMutableArray<NSMutableDictionary *> *_projects;
    NSMutableDictionary *_settings;
}

+ (instancetype)shared {
    static RAEStore *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ store = [[RAEStore alloc] init]; });
    return store;
}

+ (NSString *)supportDirectory {
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject
                     stringByAppendingPathComponent:@"RAE"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    return dir;
}

- (NSString *)projectsPath {
    return [[RAEStore supportDirectory] stringByAppendingPathComponent:@"projects.plist"];
}

- (instancetype)init {
    if ((self = [super init])) {
        _projects = [NSMutableArray array];
        NSData *data = [NSData dataWithContentsOfFile:[self projectsPath]];
        // Read everything back as mutable so profiles can be edited after a restart.
        id saved = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainers format:NULL error:NULL] : nil;
        if ([saved isKindOfClass:NSArray.class]) {
            for (id d in saved) if ([d isKindOfClass:NSMutableDictionary.class]) [_projects addObject:d];
        }
    }
    return self;
}

- (NSMutableArray *)projects { return _projects; }

#pragma mark - Settings

// Settings are saved in a file in this app's own folder (the same place the projects live), because
// NSUserDefaults is not reliable for jailbroken apps. The file is written at every change.
- (NSString *)settingsPath {
    return [[RAEStore supportDirectory] stringByAppendingPathComponent:@"settings.plist"];
}

- (NSMutableDictionary *)settingsDict {
    if (!_settings) {
        _settings = [NSMutableDictionary dictionaryWithContentsOfFile:[self settingsPath]] ?: [NSMutableDictionary dictionary];
    }
    return _settings;
}

- (NSString *)stringForKey:(NSString *)key {
    NSString *v = [self settingsDict][key];
    if (![v isKindOfClass:NSString.class]) v = [NSUserDefaults.standardUserDefaults stringForKey:key];   // keys saved by version 1.0.0
    return v ?: @"";
}

- (void)setString:(NSString *)value forKey:(NSString *)key {
    NSString *clean = [(value ?: @"") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    [self settingsDict][key] = clean;
    [[self settingsDict] writeToFile:[self settingsPath] atomically:YES];
    [NSUserDefaults.standardUserDefaults setObject:clean forKey:key];
}

+ (NSArray<NSDictionary *> *)providers {
    return @[
        @{@"id": @"gemini", @"name": @"Google Gemini (free tier)", @"kind": @"openai",
          @"url": @"https://generativelanguage.googleapis.com/v1beta/openai", @"model": @"gemini-2.0-flash"},
        @{@"id": @"groq", @"name": @"Groq (free tier)", @"kind": @"openai",
          @"url": @"https://api.groq.com/openai/v1", @"model": @"llama-3.3-70b-versatile"},
        @{@"id": @"openrouter", @"name": @"OpenRouter (free models)", @"kind": @"openai",
          @"url": @"https://openrouter.ai/api/v1", @"model": @"meta-llama/llama-3.3-70b-instruct:free"},
        @{@"id": @"custom", @"name": @"Custom (any OpenAI-compatible)", @"kind": @"openai", @"url": @"", @"model": @""},
        @{@"id": @"anthropic", @"name": @"Claude (paid)", @"kind": @"anthropic",
          @"url": @"https://api.anthropic.com", @"model": @"claude-sonnet-5-5"},
    ];
}

- (NSString *)provider {
    NSString *p = [self stringForKey:@"provider"];
    for (NSDictionary *d in RAEStore.providers) if ([d[@"id"] isEqualToString:p]) return p;
    return @"gemini";   // a free one by default
}
- (void)setProvider:(NSString *)v { [self setString:v forKey:@"provider"]; }

- (NSDictionary *)providerInfo {
    for (NSDictionary *d in RAEStore.providers) if ([d[@"id"] isEqualToString:self.provider]) return d;
    return RAEStore.providers.firstObject;
}

- (NSString *)keyFor:(NSString *)suffix { return [NSString stringWithFormat:@"ai.%@.%@", self.provider, suffix]; }

- (NSString *)anthropicKey {
    NSString *v = [self stringForKey:[self keyFor:@"key"]];
    if (!v.length && [self.provider isEqualToString:@"anthropic"]) v = [self stringForKey:@"anthropicKey"];   // saved by older versions
    return v;
}
- (void)setAnthropicKey:(NSString *)v { [self setString:v forKey:[self keyFor:@"key"]]; }
- (NSString *)model { NSString *m = [self stringForKey:[self keyFor:@"model"]]; return m.length ? m : self.providerInfo[@"model"]; }
- (void)setModel:(NSString *)v { [self setString:v forKey:[self keyFor:@"model"]]; }
- (NSString *)baseURL { NSString *u = [self stringForKey:[self keyFor:@"url"]]; return u.length ? u : self.providerInfo[@"url"]; }
- (void)setBaseURL:(NSString *)v { [self setString:v forKey:[self keyFor:@"url"]]; }
- (NSString *)githubToken { return [self stringForKey:@"githubToken"]; }
- (void)setGithubToken:(NSString *)v { [self setString:v forKey:@"githubToken"]; }
- (NSString *)buildsRepo { return [self stringForKey:@"buildsRepo"]; }
- (void)setBuildsRepo:(NSString *)v { [self setString:v forKey:@"buildsRepo"]; }

#pragma mark - Projects

+ (NSString *)slugForBundleID:(NSString *)bundleID {
    NSMutableString *slug = [NSMutableString string];
    for (NSUInteger i = 0; i < bundleID.length; i++) {
        unichar c = [bundleID.lowercaseString characterAtIndex:i];
        if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) [slug appendFormat:@"%C", c];
        else if (slug.length && ![slug hasSuffix:@"-"]) [slug appendString:@"-"];
    }
    while ([slug hasSuffix:@"-"]) [slug deleteCharactersInRange:NSMakeRange(slug.length - 1, 1)];
    if (slug.length > 60) [slug deleteCharactersInRange:NSMakeRange(60, slug.length - 60)];
    return slug.length ? slug : @"app";
}

- (NSMutableDictionary *)addProjectForAnalysis:(NSDictionary *)analysis facts:(NSString *)facts {
    NSString *bundleID = analysis[@"bundleId"] ?: @"unknown";
    NSString *slug = [RAEStore slugForBundleID:bundleID];
    NSMutableDictionary *project = nil;
    for (NSMutableDictionary *p in _projects) if ([p[@"id"] isEqualToString:slug]) project = p;
    if (!project) {
        project = [NSMutableDictionary dictionary];
        project[@"id"] = slug;
        project[@"name"] = [NSString stringWithFormat:@"%@ Boost", analysis[@"appName"] ?: @"App"];
        project[@"created"] = @([NSDate date].timeIntervalSince1970);
        [_projects insertObject:project atIndex:0];
    }
    project[@"analysis"] = analysis;
    project[@"facts"] = facts;
    project[@"profile"] = [analysis[@"profile"] mutableCopy];
    [project removeObjectForKey:@"aiReport"];
    [self save];
    return project;
}

- (void)deleteProject:(NSDictionary *)project {
    [_projects removeObject:(NSMutableDictionary *)project];
    [self save];
}

- (void)save {
    [_projects writeToFile:[self projectsPath] atomically:YES];
    [NSUserDefaults.standardUserDefaults synchronize];
}

@end
