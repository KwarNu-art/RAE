#import "RAEGitHub.h"
#import "RAEGenerator.h"
#import "RAENet.h"
#import "RAEStore.h"

static NSError *GHError(NSString *message) {
    return [NSError errorWithDomain:@"RAE" code:20 userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation RAEGitHub

// One GitHub API call. `body` may be nil. Returns parsed JSON (or nil) and the HTTP status.
+ (id)call:(NSString *)method path:(NSString *)path body:(NSDictionary *)body token:(NSString *)token status:(NSInteger *)status {
    NSURL *url = [NSURL URLWithString:[@"https://api.github.com" stringByAppendingString:path]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = method;
    [req setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [req setValue:@"2022-11-28" forHTTPHeaderField:@"X-GitHub-Api-Version"];
    [req setValue:@"RAE-iOS" forHTTPHeaderField:@"User-Agent"];
    if (body) {
        req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
        [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    }
    NSInteger code = 0;
    NSData *data = [RAENet send:req status:&code error:NULL];
    if (status) *status = code;
    if (!data.length) return nil;
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
}

+ (NSString *)messageFrom:(id)json fallback:(NSString *)fallback {
    if ([json isKindOfClass:NSDictionary.class] && [json[@"message"] isKindOfClass:NSString.class]) return json[@"message"];
    return fallback;
}

// Creates or updates one file. Skips it when the content is already identical.
+ (NSString *)putFile:(NSString *)path data:(NSData *)data repo:(NSString *)repo branch:(NSString *)branch token:(NSString *)token {
    NSString *encoded = [path stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
    NSInteger status = 0;
    id existing = [self call:@"GET" path:[NSString stringWithFormat:@"/repos/%@/contents/%@?ref=%@", repo, encoded, branch] body:nil token:token status:&status];
    NSString *sha = nil;
    if (status == 200 && [existing isKindOfClass:NSDictionary.class]) {
        sha = existing[@"sha"];
        NSString *old = [[existing[@"content"] ?: @"" componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] componentsJoinedByString:@""];
        NSData *oldData = [[NSData alloc] initWithBase64EncodedString:old options:0];
        if (oldData && [oldData isEqualToData:data]) return nil;
    }
    NSMutableDictionary *body = [@{@"message": [NSString stringWithFormat:@"RAE: update %@", path.lastPathComponent],
                                   @"content": [data base64EncodedStringWithOptions:0],
                                   @"branch": branch} mutableCopy];
    if (sha) body[@"sha"] = sha;
    id result = [self call:@"PUT" path:[NSString stringWithFormat:@"/repos/%@/contents/%@", repo, encoded] body:body token:token status:&status];
    if (status != 200 && status != 201) {
        NSString *msg = [self messageFrom:result fallback:[NSString stringWithFormat:@"HTTP %ld", (long)status]];
        if ([path hasPrefix:@".github/workflows"]) msg = [msg stringByAppendingString:@" (the GitHub token needs the 'repo' and 'workflow' permissions)"];
        return [NSString stringWithFormat:@"Could not upload %@: %@", path.lastPathComponent, msg];
    }
    return nil;
}

+ (NSString *)buildProject:(NSMutableDictionary *)project token:(NSString *)token repoSetting:(NSString *)repoSetting
                  progress:(void (^)(NSString *))progress error:(NSError **)error {
    if (!token.length) {
        if (error) *error = GHError(@"Add your GitHub token in Settings first.");
        return nil;
    }
    NSInteger status = 0;

    progress(@"Checking your GitHub token…");
    id user = [self call:@"GET" path:@"/user" body:nil token:token status:&status];
    NSString *login = [user isKindOfClass:NSDictionary.class] ? user[@"login"] : nil;
    if (status != 200 || !login) {
        if (error) *error = GHError([NSString stringWithFormat:@"GitHub did not accept the token: %@", [self messageFrom:user fallback:[NSString stringWithFormat:@"HTTP %ld", (long)status]]]);
        return nil;
    }

    NSString *repo = repoSetting.length ? repoSetting : [login stringByAppendingString:@"/RAE-Builds"];
    NSArray *parts = [repo componentsSeparatedByString:@"/"];
    if (parts.count != 2 || ![parts[0] length] || ![parts[1] length]) {
        if (error) *error = GHError(@"The builds repository must look like owner/name.");
        return nil;
    }

    progress([NSString stringWithFormat:@"Checking %@…", repo]);
    id repoInfo = [self call:@"GET" path:[NSString stringWithFormat:@"/repos/%@", repo] body:nil token:token status:&status];
    if (status == 404) {
        progress(@"Creating the builds repository…");
        repoInfo = [self call:@"POST" path:@"/user/repos" body:@{
            @"name": parts[1], @"description": @"Performance tweaks built by RAE",
            @"auto_init": @YES, @"private": @NO } token:token status:&status];
        if (status != 201) {
            if (error) *error = GHError([NSString stringWithFormat:@"Could not create %@: %@", repo, [self messageFrom:repoInfo fallback:[NSString stringWithFormat:@"HTTP %ld", (long)status]]]);
            return nil;
        }
        [NSThread sleepForTimeInterval:4];
    } else if (status != 200) {
        if (error) *error = GHError([NSString stringWithFormat:@"Cannot use %@: %@", repo, [self messageFrom:repoInfo fallback:[NSString stringWithFormat:@"HTTP %ld", (long)status]]]);
        return nil;
    }
    NSString *branch = [repoInfo isKindOfClass:NSDictionary.class] && [repoInfo[@"default_branch"] length] ? repoInfo[@"default_branch"] : @"main";
    if ([repoInfo isKindOfClass:NSDictionary.class] && [repoInfo[@"private"] boolValue]) {
        progress(@"Note: a private repo uses much more of your free build minutes.");
    }

    NSInteger build = [project[@"buildNumber"] integerValue] + 1;
    NSError *genError = nil;
    NSDictionary *files = [RAEGenerator projectFilesForProject:project build:build error:&genError];
    NSData *workflow = [RAEGenerator workflowFile];
    if (!files || !workflow) {
        if (error) *error = genError ?: GHError(@"The build workflow template is missing from the app.");
        return nil;
    }
    NSMutableDictionary *all = [files mutableCopy];
    all[@".github/workflows/build.yml"] = workflow;
    NSUInteger i = 0;
    for (NSString *path in [all.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        progress([NSString stringWithFormat:@"Uploading project files (%lu/%lu)…", (unsigned long)++i, (unsigned long)all.count]);
        NSString *problem = [self putFile:path data:all[path] repo:repo branch:branch token:token];
        if (problem) { if (error) *error = GHError(problem); return nil; }
    }
    project[@"buildNumber"] = @(build);
    [RAEStore.shared save];

    // Start the build. A brand new workflow file can take a few seconds to be recognised.
    NSDate *dispatched = [NSDate date];
    BOOL started = NO;
    NSString *dispatchProblem = nil;
    for (int attempt = 0; attempt < 8 && !started; attempt++) {
        progress(@"Starting the online build…");
        id res = [self call:@"POST" path:[NSString stringWithFormat:@"/repos/%@/actions/workflows/build.yml/dispatches", repo]
                       body:@{@"ref": branch, @"inputs": @{@"project": project[@"id"]}} token:token status:&status];
        if (status == 204) { started = YES; break; }
        dispatchProblem = [self messageFrom:res fallback:[NSString stringWithFormat:@"HTTP %ld", (long)status]];
        if (status == 401 || status == 403) break;
        [NSThread sleepForTimeInterval:5];
    }
    if (!started) {
        if (error) *error = GHError([NSString stringWithFormat:@"Could not start the build: %@", dispatchProblem]);
        return nil;
    }

    // Find the run we just started.
    NSISO8601DateFormatter *iso = [[NSISO8601DateFormatter alloc] init];
    NSNumber *runID = nil;
    NSString *runURL = nil;
    for (int attempt = 0; attempt < 30 && !runID; attempt++) {
        [NSThread sleepForTimeInterval:4];
        id runs = [self call:@"GET" path:[NSString stringWithFormat:@"/repos/%@/actions/runs?event=workflow_dispatch&per_page=10", repo] body:nil token:token status:&status];
        for (NSDictionary *run in ([runs isKindOfClass:NSDictionary.class] ? runs[@"workflow_runs"] : @[])) {
            NSDate *created = [iso dateFromString:run[@"created_at"] ?: @""];
            if (created && [created timeIntervalSinceDate:dispatched] > -30 && [run[@"path"] hasSuffix:@"build.yml"]) {
                runID = run[@"id"];
                runURL = run[@"html_url"];
                break;
            }
        }
    }
    if (!runID) {
        if (error) *error = GHError(@"The build did not appear on GitHub. Open the Actions tab of your builds repository to check.");
        return nil;
    }
    project[@"runURL"] = runURL ?: @"";

    // Wait for it to finish (a first build takes about 3 to 5 minutes).
    NSString *conclusion = nil;
    NSTimeInterval started_at = [NSDate timeIntervalSinceReferenceDate];
    while ([NSDate timeIntervalSinceReferenceDate] - started_at < 25 * 60) {
        id run = [self call:@"GET" path:[NSString stringWithFormat:@"/repos/%@/actions/runs/%@", repo, runID] body:nil token:token status:&status];
        NSString *state = [run isKindOfClass:NSDictionary.class] ? run[@"status"] : nil;
        if ([state isEqualToString:@"completed"]) { conclusion = run[@"conclusion"] ?: @"unknown"; break; }
        NSInteger elapsed = (NSInteger)([NSDate timeIntervalSinceReferenceDate] - started_at);
        progress([NSString stringWithFormat:@"Building online… %@ (%ld:%02ld)", state ?: @"waiting", (long)(elapsed / 60), (long)(elapsed % 60)]);
        [NSThread sleepForTimeInterval:10];
    }
    if (![conclusion isEqualToString:@"success"]) {
        NSString *msg = conclusion ? [NSString stringWithFormat:@"The online build %@. Open the log: %@", conclusion, runURL] : @"The online build took too long.";
        if (error) *error = GHError(msg);
        return nil;
    }

    progress(@"Downloading the .deb…");
    NSString *tag = [NSString stringWithFormat:@"%@-v1.0.%ld", project[@"id"], (long)build];
    NSString *assetURL = nil, *assetName = nil;
    for (int attempt = 0; attempt < 6 && !assetURL; attempt++) {
        id release = [self call:@"GET" path:[NSString stringWithFormat:@"/repos/%@/releases/tags/%@", repo, tag] body:nil token:token status:&status];
        for (NSDictionary *asset in ([release isKindOfClass:NSDictionary.class] ? release[@"assets"] : @[])) {
            if ([asset[@"name"] hasSuffix:@".deb"]) { assetURL = asset[@"browser_download_url"]; assetName = asset[@"name"]; break; }
        }
        if (!assetURL) [NSThread sleepForTimeInterval:4];
    }
    if (!assetURL) {
        if (error) *error = GHError(@"The build finished but no .deb was found in its release.");
        return nil;
    }
    NSString *dir = [[RAEStore supportDirectory] stringByAppendingPathComponent:@"Builds"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *path = [dir stringByAppendingPathComponent:assetName];
    NSString *problem = [RAENet downloadURL:[NSURL URLWithString:assetURL] toPath:path error:NULL];
    if (problem) {
        if (error) *error = GHError([NSString stringWithFormat:@"Could not download the .deb: %@", problem]);
        return nil;
    }
    return path;
}

@end
