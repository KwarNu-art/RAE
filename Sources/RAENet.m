#import "RAENet.h"

@implementation RAENet

+ (NSURLSession *)session {
    static NSURLSession *session;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURLSessionConfiguration *c = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        c.timeoutIntervalForRequest = 120;
        c.timeoutIntervalForResource = 900;
        session = [NSURLSession sessionWithConfiguration:c];
    });
    return session;
}

+ (NSData *)send:(NSURLRequest *)request status:(NSInteger *)status error:(NSError **)error {
    __block NSData *body = nil;
    __block NSInteger code = 0;
    __block NSError *err = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [[[self session] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *e) {
        body = data;
        err = e;
        code = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        dispatch_semaphore_signal(done);
    }] resume];
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    if (status) *status = code;
    if (error) *error = err;
    return body;
}

+ (NSString *)downloadURL:(NSURL *)url toPath:(NSString *)path error:(NSError **)error {
    __block NSString *message = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [[[self session] downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *e) {
        NSInteger code = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        if (e || !location || code != 200) {
            message = e.localizedDescription ?: [NSString stringWithFormat:@"download failed (HTTP %ld)", (long)code];
        } else {
            [NSFileManager.defaultManager removeItemAtPath:path error:NULL];
            NSError *moveError = nil;
            if (![NSFileManager.defaultManager moveItemAtURL:location toURL:[NSURL fileURLWithPath:path] error:&moveError]) {
                message = moveError.localizedDescription;
            }
        }
        dispatch_semaphore_signal(done);
    }] resume];
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    return message;
}

@end
