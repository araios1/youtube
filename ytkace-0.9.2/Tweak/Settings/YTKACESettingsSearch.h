#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSArray<NSDictionary *> *YTKACEFilterSettings(NSString *query);
FOUNDATION_EXPORT void YTKACEPresentSettingsSearchOverlay(UIViewController *host);
FOUNDATION_EXPORT void YTKACEOpenSettingsRecord(NSDictionary *record,
                                                UIViewController *presenter);

NS_ASSUME_NONNULL_END
