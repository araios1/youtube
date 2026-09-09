#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../Downloads/DownloadLog.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>

static BOOL YTKACECastYes(id receiver, SEL selector) {
    (void)receiver;
    (void)selector;
    return YES;
}

static BOOL YTKACECastNo(id receiver, SEL selector) {
    (void)receiver;
    (void)selector;
    return NO;
}

static NSInteger YTKACECastAllowedStatus(id receiver, SEL selector) {
    (void)receiver;
    (void)selector;
    return 1;
}

static void YTKACESkipLocalNetworkPage(id receiver,
                                       SEL selector,
                                       id completion) {
    (void)receiver;
    (void)selector;
    YTKACEDownloadLog(@"cast", @"permission page bypassed");
    YTKACEStartCastDiscovery();
    if (completion == nil) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            ((void (^)(BOOL))completion)(YES);
        } @catch (__unused NSException *exception) {
            YTKACEDownloadLog(@"cast", @"permission completion failed");
        }
    });
}

static void YTKACERefreshCastHooks(void) {
    YTKACEInstallInstanceHook(@"MDXRoutePresentationController",
                              @"hasSufficientLocalNetworkPermissions",
                              (IMP)YTKACECastYes,
                              NULL);
    YTKACEInstallInstanceHook(@"MDXLocalNetworkPermissions",
                              @"lastKnownPermissionsStatus",
                              (IMP)YTKACECastAllowedStatus,
                              NULL);
    YTKACEInstallInstanceHook(@"MDXLocalNetworkPermissions",
                              @"isAuthorized",
                              (IMP)YTKACECastYes,
                              NULL);
    YTKACEInstallInstanceHook(@"MDXLocalStorage",
                              @"localNetworkPermissionsStatus",
                              (IMP)YTKACECastAllowedStatus,
                              NULL);
    YTKACEInstallInstanceHook(
        @"MDXPermissionsController",
        @"showLocalNetworkPermissionsRequiredPageWithCompletion:",
        (IMP)YTKACESkipLocalNetworkPage,
        NULL
    );
    YTKACEInstallInstanceHook(@"CADPLocalNetworkPermissionInfo",
                              @"isLocalNetworkPermissionAllowed",
                              (IMP)YTKACECastYes,
                              NULL);
    YTKACEInstallInstanceHook(@"CADPLocalNetworkPermissionInfo",
                              @"wasLocalNetworkPermissionAllowed",
                              (IMP)YTKACECastYes,
                              NULL);
    YTKACEInstallInstanceHook(
        @"CADPLocalNetworkPermissionInfo",
        @"shouldPresentLocalNetworkAccessPermissionDialog",
        (IMP)YTKACECastNo,
        NULL
    );
    YTKACEInstallInstanceHook(
        @"YTBAMediaHubUiDeviceItemsResult",
        @"shouldShowLocalNetworkPermissionPrompt",
        (IMP)YTKACECastNo,
        NULL
    );
}

void YTKACEStartCastDiscovery(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            Class contextClass = NSClassFromString(@"GCKCastContext");
            SEL sharedSelector = NSSelectorFromString(@"sharedInstance");
            if (contextClass == Nil ||
                ![contextClass respondsToSelector:sharedSelector]) {
                YTKACEDownloadLog(@"cast", @"context unavailable");
                return;
            }
            id context = ((id (*)(id, SEL))objc_msgSend)(contextClass,
                                                         sharedSelector);
            SEL managerSelector = NSSelectorFromString(@"discoveryManager");
            if (context == nil || ![context respondsToSelector:managerSelector]) {
                YTKACEDownloadLog(@"cast", @"manager unavailable");
                return;
            }
            id manager = ((id (*)(id, SEL))objc_msgSend)(context,
                                                         managerSelector);
            SEL startSelector = NSSelectorFromString(@"startDiscovery");
            if (manager != nil && [manager respondsToSelector:startSelector]) {
                ((void (*)(id, SEL))objc_msgSend)(manager, startSelector);
                YTKACEDownloadLog(@"cast", @"discovery started");
                dispatch_after(
                    dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                    dispatch_get_main_queue(), ^{
                        SEL countSelector = NSSelectorFromString(@"deviceCount");
                        if ([manager respondsToSelector:countSelector]) {
                            NSUInteger count = ((NSUInteger (*)(id, SEL))objc_msgSend)(
                                manager,
                                countSelector
                            );
                            YTKACEDownloadLog(@"cast", @"devices=%lu",
                                             (unsigned long)count);
                        }
                    }
                );
            }
        } @catch (__unused NSException *exception) {
            YTKACEDownloadLog(@"cast", @"discovery exception");
        }
    });
}

void YTKACEInstallCastCompatibilityHooks(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        YTKACERefreshCastHooks();

        [NSNotificationCenter.defaultCenter
            addObserverForName:UIApplicationDidBecomeActiveNotification
                    object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(__unused NSNotification *notification) {
                        YTKACERefreshCastHooks();
                        YTKACEDownloadLog(@"cast", @"app active");
                    }];
    });
}
