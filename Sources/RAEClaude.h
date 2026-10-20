#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RAEClaude : NSObject

// Asks Claude for a detailed performance report about the analysed app. Blocking: call from a background queue.
// `suggestedProfile` is validated against what the generator supports; it may be nil.
+ (nullable NSString *)reportForProject:(NSDictionary *)project
                                 apiKey:(NSString *)apiKey
                                  model:(NSString *)model
                       suggestedProfile:(NSDictionary *_Nullable *_Nullable)suggestedProfile
                                  error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
