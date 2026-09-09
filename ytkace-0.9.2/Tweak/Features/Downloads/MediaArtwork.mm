#import "MediaArtwork.h"

#import <AVFoundation/AVFoundation.h>

NSData *YTKACEMediaArtworkData(NSURL *URL) {
    NSURL *base = URL.URLByDeletingPathExtension;
    for (NSString *extension in @[@"jpg", @"png"]) {
        NSData *data = [NSData dataWithContentsOfURL:
            [base URLByAppendingPathExtension:extension]];
        if (data.length != 0) return data;
    }
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:URL options:nil];
    NSArray<AVMetadataItem *> *items = [AVMetadataItem
        metadataItemsFromArray:asset.commonMetadata
        filteredByIdentifier:AVMetadataCommonIdentifierArtwork];
    id value = items.firstObject.value;
    if ([value isKindOfClass:NSData.class]) return value;
    if ([value respondsToSelector:@selector(dataValue)]) return [value dataValue];
    return nil;
}

UIImage *YTKACEMediaArtworkImage(NSURL *URL) {
    NSData *data = YTKACEMediaArtworkData(URL);
    return data.length == 0 ? nil : [UIImage imageWithData:data];
}
