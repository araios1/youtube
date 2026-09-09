#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT UIImage *YTKACEDownloadGlyphImage(void);

FOUNDATION_EXPORT void YTKACESaveVideoToPhotosFile(
    NSURL *url, void (^_Nullable completion)(BOOL success, NSError *_Nullable error));

@interface YTKACEDownloadCoordinator : NSObject
+ (instancetype)sharedCoordinator;
@property(nonatomic, strong, nullable) id playerResponse;
- (void)showDownloadMenu;
- (void)showDownloadMenuFromButton:(nullable UIButton *)button;
- (void)showShortsDownloadMenuFromView:(UIView *)sourceView;
@end

NS_ASSUME_NONNULL_END
