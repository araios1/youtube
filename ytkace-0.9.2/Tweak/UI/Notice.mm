#import "Notice.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>

BOOL YTKACEShowYouTubeDialog(NSString *title, NSString *message) {
    Class alertClass = NSClassFromString(@"YTAlertView");
    SEL infoSelector = NSSelectorFromString(@"infoDialog");
    if (alertClass == Nil || ![alertClass respondsToSelector:infoSelector]) {
        return NO;
    }
    @try {
        id alert = ((id (*)(id, SEL))objc_msgSend)(alertClass, infoSelector);
        SEL titleSelector = NSSelectorFromString(@"setTitle:");
        SEL subtitleSelector = NSSelectorFromString(@"setSubtitle:");
        SEL showSelector = NSSelectorFromString(@"show");
        if (alert == nil || ![alert respondsToSelector:titleSelector] ||
            ![alert respondsToSelector:subtitleSelector] ||
            ![alert respondsToSelector:showSelector]) {
            return NO;
        }
        ((void (*)(id, SEL, id))objc_msgSend)(alert, titleSelector, title ?: @"");
        ((void (*)(id, SEL, id))objc_msgSend)(alert, subtitleSelector, message ?: @"");
        ((void (*)(id, SEL))objc_msgSend)(alert, showSelector);
        return YES;
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

BOOL YTKACEShowYouTubeConfirmation(NSString *title,
                                    NSString *message,
                                    NSString *actionTitle,
                                    dispatch_block_t action) {
    Class alertClass = NSClassFromString(@"YTAlertView");
    SEL dialogSelector =
        NSSelectorFromString(@"confirmationDialogWithAction:actionTitle:");
    if (alertClass == Nil || ![alertClass respondsToSelector:dialogSelector]) {
        return NO;
    }
    @try {
        id alert = ((id (*)(id, SEL, id, id))objc_msgSend)(
            alertClass,
            dialogSelector,
            [action copy],
            actionTitle ?: @"Continue"
        );
        SEL titleSelector = NSSelectorFromString(@"setTitle:");
        SEL subtitleSelector = NSSelectorFromString(@"setSubtitle:");
        SEL showSelector = NSSelectorFromString(@"show");
        if (alert == nil || ![alert respondsToSelector:titleSelector] ||
            ![alert respondsToSelector:subtitleSelector] ||
            ![alert respondsToSelector:showSelector]) {
            return NO;
        }
        ((void (*)(id, SEL, id))objc_msgSend)(alert, titleSelector, title ?: @"");
        ((void (*)(id, SEL, id))objc_msgSend)(alert, subtitleSelector, message ?: @"");
        ((void (*)(id, SEL))objc_msgSend)(alert, showSelector);
        return YES;
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

static UIViewController *YTKACENoticeController(void) {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive ||
            ![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }
        for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
            if (candidate.isKeyWindow) {
                window = candidate;
                break;
            }
        }
    }
    UIViewController *controller = window.rootViewController;
    while (controller.presentedViewController != nil) {
        controller = controller.presentedViewController;
    }
    if ([controller isKindOfClass:UINavigationController.class]) {
        controller = ((UINavigationController *)controller).visibleViewController;
    }
    if ([controller isKindOfClass:UITabBarController.class]) {
        controller = ((UITabBarController *)controller).selectedViewController;
    }
    return controller;
}

void YTKACEShowNotice(NSString *message) {
    if (message.length == 0) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *host = YTKACENoticeController().view;
        if (host.window == nil) return;
        UIView *old = [host viewWithTag:0x594B4E54];
        [old removeFromSuperview];
        UIView *banner = [UIView new];
        banner.tag = 0x594B4E54;
        banner.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.94];
        banner.layer.cornerRadius = 12.0;
        banner.layer.masksToBounds = YES;
        banner.translatesAutoresizingMaskIntoConstraints = NO;
        UILabel *label = [UILabel new];
        label.text = message;
        label.textColor = UIColor.whiteColor;
        label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
        label.textAlignment = NSTextAlignmentCenter;
        label.numberOfLines = 0;
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [banner addSubview:label];
        [host addSubview:banner];
        UILayoutGuide *safe = host.safeAreaLayoutGuide;
        [NSLayoutConstraint activateConstraints:@[
            [banner.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
            [banner.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-54.0],
            [banner.widthAnchor constraintGreaterThanOrEqualToConstant:160.0],
            [banner.widthAnchor constraintLessThanOrEqualToAnchor:safe.widthAnchor constant:-28.0],
            [label.topAnchor constraintEqualToAnchor:banner.topAnchor constant:12.0],
            [label.bottomAnchor constraintEqualToAnchor:banner.bottomAnchor constant:-12.0],
            [label.leadingAnchor constraintEqualToAnchor:banner.leadingAnchor constant:16.0],
            [label.trailingAnchor constraintEqualToAnchor:banner.trailingAnchor constant:-16.0]
        ]];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                if (banner.superview != nil) {
                    [UIView animateWithDuration:0.2 animations:^{ banner.alpha = 0.0; }
                        completion:^(__unused BOOL finished) { [banner removeFromSuperview]; }];
                }
            });
    });
}
