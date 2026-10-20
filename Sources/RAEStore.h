#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Settings and the list of analysed apps. Everything lives in this app's own container on the phone.
@interface RAEStore : NSObject

+ (instancetype)shared;

@property (nonatomic, copy) NSString *anthropicKey;
@property (nonatomic, copy) NSString *model;
@property (nonatomic, copy) NSString *githubToken;
@property (nonatomic, copy) NSString *buildsRepo;   // "owner/name", empty = choose automatically

@property (nonatomic, readonly) NSMutableArray<NSMutableDictionary *> *projects;

// Creates a project for an analysis (or refreshes the one for the same bundle id).
- (NSMutableDictionary *)addProjectForAnalysis:(NSDictionary *)analysis facts:(NSString *)facts;
- (void)deleteProject:(NSDictionary *)project;
- (void)save;

+ (NSString *)supportDirectory;

@end

NS_ASSUME_NONNULL_END
