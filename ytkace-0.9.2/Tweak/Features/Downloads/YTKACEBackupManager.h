#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^YTKACEBackupCreationCompletion)(NSURL * _Nullable URL,
                                                NSError * _Nullable error);
typedef void (^YTKACEBackupRestoreCompletion)(NSError * _Nullable error);

@interface YTKACEBackupManager : NSObject

+ (void)createBackupWithCompletion:(YTKACEBackupCreationCompletion)completion;
+ (void)restoreBackupFromURL:(NSURL *)URL
                  completion:(YTKACEBackupRestoreCompletion)completion;

@end

NS_ASSUME_NONNULL_END
