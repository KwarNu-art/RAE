#import <Foundation/Foundation.h>

// Small blocking HTTP helper. Always call it from a background queue.
@interface RAENet : NSObject
+ (NSData *)send:(NSURLRequest *)request status:(NSInteger *)status error:(NSError **)error;
+ (NSString *)downloadURL:(NSURL *)url toPath:(NSString *)path error:(NSError **)error;   // returns nil on success, else a message
@end
