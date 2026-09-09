#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^YTKACEMediaImportCompletion)(NSUInteger importedCount,
                                            NSError * _Nullable error);

@interface YTKACEMediaImporter : NSObject

+ (void)importURLs:(NSArray<NSURL *> *)URLs
          category:(NSString *)category
        completion:(YTKACEMediaImportCompletion)completion;

@end

NS_ASSUME_NONNULL_END
