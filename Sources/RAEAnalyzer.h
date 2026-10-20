#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Static analysis of a decrypted IPA, done entirely on the phone. Nothing is modified and nothing is run.
@interface RAEAnalyzer : NSObject

// Returns a property-list friendly dictionary describing the app, or nil with `error` set.
+ (nullable NSDictionary *)analyzeIPAAtPath:(NSString *)ipaPath
                                   progress:(nullable void (^)(NSString *step))progress
                                      error:(NSError **)error;

// Human readable report built from the dictionary above.
+ (NSString *)factsReportForAnalysis:(NSDictionary *)analysis;

@end

NS_ASSUME_NONNULL_END
