#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^YTKACESponsorCompletion)(
    NSArray<NSDictionary<NSString *, id> *> *segments
);

@interface YTKACESponsorClient : NSObject
+ (instancetype)sharedClient;
- (void)segmentsForVideoID:(NSString *)videoID
                completion:(YTKACESponsorCompletion)completion;
@end

NS_ASSUME_NONNULL_END
