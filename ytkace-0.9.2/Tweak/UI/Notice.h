#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT void YTKACEShowNotice(NSString *message);
FOUNDATION_EXPORT BOOL YTKACEShowYouTubeDialog(NSString *title,
                                                NSString *message);
FOUNDATION_EXPORT BOOL YTKACEShowYouTubeConfirmation(
    NSString *title,
    NSString *message,
    NSString *actionTitle,
    dispatch_block_t action
);

NS_ASSUME_NONNULL_END
