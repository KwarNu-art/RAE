#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Settings and the list of analysed apps. Everything lives in this app's own container on the phone.
@interface RAEStore : NSObject

+ (instancetype)shared;

// The AI provider (Claude, Gemini, Groq, OpenRouter or a custom OpenAI-compatible one). Each keeps its own key, model and address.
@property (nonatomic, copy) NSString *provider;      // provider id
@property (nonatomic, copy) NSString *anthropicKey;  // key of the selected provider (name kept from version 1)
@property (nonatomic, copy) NSString *model;
@property (nonatomic, copy) NSString *baseURL;
+ (NSArray<NSDictionary *> *)providers;               // @{id, name, url, model, kind}
- (NSDictionary *)providerInfo;
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
