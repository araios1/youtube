#import "Hooking.h"

static NSObject *YTKACEHookLock(void) {
    static NSObject *lock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        lock = [NSObject new];
    });
    return lock;
}

static NSMutableSet<NSString *> *YTKACEHookKeys(void) {
    static NSMutableSet<NSString *> *keys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = [NSMutableSet set];
    });
    return keys;
}

static BOOL YTKACEInstallHook(NSString *className,
                              NSString *selectorName,
                              BOOL classMethod,
                              IMP replacement,
                              IMP *originalStorage) {
    if (className.length == 0 || selectorName.length == 0 || replacement == NULL) {
        return NO;
    }

    Class cls = NSClassFromString(className);
    if (cls == Nil) {
        return NO;
    }

    Class targetClass = classMethod ? object_getClass(cls) : cls;
    if (targetClass == Nil) {
        return NO;
    }

    SEL selector = NSSelectorFromString(selectorName);
    Method method = class_getInstanceMethod(targetClass, selector);
    if (method == NULL) {
        return NO;
    }

    NSString *key = [NSString stringWithFormat:@"%@|%@|%@",
                     className,
                     classMethod ? @"+" : @"-",
                     selectorName];

    @synchronized (YTKACEHookLock()) {
        if ([YTKACEHookKeys() containsObject:key]) {
            return YES;
        }

        IMP original = method_getImplementation(method);
        const char *types = method_getTypeEncoding(method);

        BOOL added = class_addMethod(targetClass, selector, replacement, types);
        if (!added) {
            Method directMethod = class_getInstanceMethod(targetClass, selector);
            if (directMethod == NULL) {
                return NO;
            }
            method_setImplementation(directMethod, replacement);
        }

        if (originalStorage != NULL) {
            *originalStorage = original;
        }
        [YTKACEHookKeys() addObject:key];
        return YES;
    }
}

BOOL YTKACEInstallInstanceHook(NSString *className,
                               NSString *selectorName,
                               IMP replacement,
                               IMP *originalStorage) {
    return YTKACEInstallHook(className, selectorName, NO, replacement, originalStorage);
}

BOOL YTKACEInstallClassHook(NSString *className,
                            NSString *selectorName,
                            IMP replacement,
                            IMP *originalStorage) {
    return YTKACEInstallHook(className, selectorName, YES, replacement, originalStorage);
}

BOOL YTKACEAddInstanceMethod(NSString *className,
                             NSString *selectorName,
                             IMP implementation,
                             const char *typeEncoding) {
    if (className.length == 0 || selectorName.length == 0 ||
        implementation == NULL || typeEncoding == NULL) {
        return NO;
    }

    Class cls = NSClassFromString(className);
    if (cls == Nil) {
        return NO;
    }

    NSString *key = [NSString stringWithFormat:@"%@|add|%@", className, selectorName];
    @synchronized (YTKACEHookLock()) {
        if ([YTKACEHookKeys() containsObject:key]) {
            return YES;
        }

        BOOL added = class_addMethod(cls,
                                     NSSelectorFromString(selectorName),
                                     implementation,
                                     typeEncoding);
        if (added) {
            [YTKACEHookKeys() addObject:key];
            [YTKACEHookKeys() addObject:
                [NSString stringWithFormat:@"%@|-|%@", className, selectorName]];
        }
        return added;
    }
}

NSUInteger YTKACEInstalledHookCount(void) {
    @synchronized (YTKACEHookLock()) {
        return YTKACEHookKeys().count;
    }
}
