#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Turns an analysis and a boost profile into the source of a small performance tweak for that one app.
@interface RAEGenerator : NSObject

+ (NSString *)tweakNameForProject:(NSDictionary *)project;      // e.g. RAEBoost_com_example_game
+ (NSString *)packageIDForProject:(NSDictionary *)project;      // e.g. com.rae.boost.com.example.game

// Files for projects/<id>/ keyed by repository path. Returns nil with `error` for an unsafe bundle id.
+ (nullable NSDictionary<NSString *, NSData *> *)projectFilesForProject:(NSDictionary *)project
                                                                  build:(NSInteger)build
                                                                  error:(NSError **)error;
+ (nullable NSData *)workflowFile;                               // .github/workflows/build.yml of the builds repo
+ (NSString *)tweakSourcePreviewForProject:(NSDictionary *)project;

@end

NS_ASSUME_NONNULL_END
