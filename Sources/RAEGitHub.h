#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Pushes a generated project to the user's own builds repository, runs the GitHub Actions build and downloads the .deb.
@interface RAEGitHub : NSObject

// Blocking: call from a background queue. Returns the local path of the .deb, or nil with `error` set.
+ (nullable NSString *)buildProject:(NSMutableDictionary *)project
                              token:(NSString *)token
                          repoSetting:(NSString *)repoSetting
                           progress:(void (^)(NSString *status))progress
                              error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
