#import "RAEClaude.h"
#import "RAENet.h"

@implementation RAEClaude

static NSError *RAEClaudeError(NSString *message) {
    return [NSError errorWithDomain:@"RAE" code:10 userInfo:@{NSLocalizedDescriptionKey: message}];
}

+ (NSString *)reportForProject:(NSDictionary *)project apiKey:(NSString *)apiKey model:(NSString *)model
              suggestedProfile:(NSDictionary **)suggestedProfile error:(NSError **)error {
    if (!apiKey.length) {
        if (error) *error = RAEClaudeError(@"Add your Anthropic API key in Settings first.");
        return nil;
    }
    NSString *facts = project[@"facts"] ?: @"";
    if (facts.length > 24000) facts = [facts substringToIndex:24000];

    NSString *system =
        @"You are a careful iOS performance engineer. You are given static facts (no code was run) about an app binary "
        @"that its owner extracted from their own device and wants to run smoothly on an iPhone 7 Plus (A10, 60 Hz, 3 GB RAM) "
        @"and on other iPhones. Explain what the app is and how it is built, where lag, high RAM, high CPU, heat and battery "
        @"drain most likely come from, and what a small performance-only tweak could safely change. "
        @"The tweak can only do these things: frame rate control (leave / smooth / cool), memory trimming, timer coalescing, "
        @"lowering background priority, and a thermal guard. It cannot change game logic, bypass protections, licences, "
        @"purchases or anti-cheat, and you must never suggest doing so. Be honest: separate facts from guesses, say when "
        @"something is uncertain, and do not promise a fixed frame rate or temperature.\n\n"
        @"Write clear sections with short plain-English explanations: 1) What this app is, 2) How it is built, "
        @"3) Likely performance problems (RAM, CPU, heat, battery), 4) What each tweak feature will do for this app and whether "
        @"to enable it, 5) Things the tweak cannot fix, 6) Practical tips for the user. "
        @"Finish with exactly one fenced json block, and nothing after it, of this form: "
        @"```json\n{\"frameMode\":0|1|2,\"memoryTrim\":true|false,\"timerSaving\":true|false,\"backgroundQuiet\":true|false,\"thermalGuard\":true|false}\n```";

    NSString *user = [NSString stringWithFormat:@"Static analysis of the app:\n\n%@\n\nCurrent suggested profile (from simple rules): %@",
                      facts, project[@"profile"] ?: @{}];

    NSDictionary *body = @{
        @"model": model.length ? model : @"claude-sonnet-5-5",
        @"max_tokens": @4000,
        @"system": system,
        @"messages": @[@{@"role": @"user", @"content": user}],
    };
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://api.anthropic.com/v1/messages"]];
    req.HTTPMethod = @"POST";
    [req setValue:apiKey forHTTPHeaderField:@"x-api-key"];
    [req setValue:@"2023-06-01" forHTTPHeaderField:@"anthropic-version"];
    [req setValue:@"application/json" forHTTPHeaderField:@"content-type"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
    req.timeoutInterval = 180;

    NSInteger status = 0;
    NSError *netError = nil;
    NSData *data = [RAENet send:req status:&status error:&netError];
    if (!data) {
        if (error) *error = RAEClaudeError([NSString stringWithFormat:@"Could not reach Claude: %@", netError.localizedDescription ?: @"no response"]);
        return nil;
    }
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (status != 200 || ![json isKindOfClass:NSDictionary.class]) {
        NSString *msg = [json[@"error"] isKindOfClass:NSDictionary.class] ? json[@"error"][@"message"] : nil;
        if (error) *error = RAEClaudeError([NSString stringWithFormat:@"Claude returned an error (HTTP %ld): %@", (long)status, msg ?: @"unknown"]);
        return nil;
    }
    NSMutableString *text = [NSMutableString string];
    for (NSDictionary *block in json[@"content"]) {
        if ([block[@"type"] isEqualToString:@"text"] && block[@"text"]) [text appendString:block[@"text"]];
    }
    if (!text.length) {
        if (error) *error = RAEClaudeError(@"Claude sent an empty answer.");
        return nil;
    }

    // Pull the json profile out of the answer, keep only values the generator supports.
    NSString *report = text;
    NSRange open = [text rangeOfString:@"```json" options:NSBackwardsSearch];
    if (open.location != NSNotFound) {
        NSString *rest = [text substringFromIndex:NSMaxRange(open)];
        NSRange close = [rest rangeOfString:@"```"];
        if (close.location != NSNotFound) {
            NSData *jd = [[rest substringToIndex:close.location] dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *p = [NSJSONSerialization JSONObjectWithData:jd options:0 error:NULL];
            if ([p isKindOfClass:NSDictionary.class] && suggestedProfile) {
                NSMutableDictionary *clean = [NSMutableDictionary dictionary];
                NSNumber *mode = p[@"frameMode"];
                if ([mode isKindOfClass:NSNumber.class]) clean[@"frameMode"] = @(MAX(0, MIN(2, mode.integerValue)));
                for (NSString *k in @[@"memoryTrim", @"timerSaving", @"backgroundQuiet", @"thermalGuard"]) {
                    if ([p[k] isKindOfClass:NSNumber.class]) clean[k] = @([p[k] boolValue]);
                }
                *suggestedProfile = clean;
            }
            report = [[text substringToIndex:open.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        }
    }
    return report;
}

@end
