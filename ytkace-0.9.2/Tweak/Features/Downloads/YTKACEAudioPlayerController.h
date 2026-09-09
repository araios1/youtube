#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class YTKACEDownloadPlaybackSession;

@interface YTKACEAudioPlayerController : UIViewController
- (instancetype)initWithSession:(YTKACEDownloadPlaybackSession *)session;
@property(nonatomic, copy, nullable) dispatch_block_t minimizeHandler;
@end

NS_ASSUME_NONNULL_END
