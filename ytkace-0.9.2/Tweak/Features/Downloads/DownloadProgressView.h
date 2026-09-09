#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^YTKACEDownloadCancelHandler)(NSString *identifier);

@interface YTKACEDownloadProgressView : NSObject
+ (instancetype)sharedView;
@property(nonatomic, copy, nullable) YTKACEDownloadCancelHandler cancelHandler;
- (void)beginJob:(NSString *)identifier
           title:(NSString *)title
    thumbnailURL:(nullable NSURL *)thumbnailURL;
- (void)updateJob:(NSString *)identifier
            stage:(NSString *)stage
         progress:(double)progress
  downloadedBytes:(int64_t)downloadedBytes
       totalBytes:(int64_t)totalBytes;
- (void)finishJob:(NSString *)identifier
          success:(BOOL)success
          message:(NSString *)message;
@end

NS_ASSUME_NONNULL_END
