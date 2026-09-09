#import "FFmpegMuxer.h"

#define AVMediaType YTKACEFFmpegMediaType
extern "C" {
#include <libavcodec/packet.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libavutil/dict.h>
#include <libavutil/error.h>
#include <libavutil/mathematics.h>
}
#undef AVMediaType

#import <AVFoundation/AVFoundation.h>

static NSString *YTKACEFFmpegMessage(int code) {
    char buffer[AV_ERROR_MAX_STRING_SIZE] = {0};
    av_strerror(code, buffer, sizeof(buffer));
    return [NSString stringWithUTF8String:buffer] ?: @"FFmpeg failed";
}

static NSError *YTKACEFFmpegError(int code, NSString *stage) {
    NSString *message = [NSString stringWithFormat:@"%@: %@", stage,
        YTKACEFFmpegMessage(code)];
    return [NSError errorWithDomain:@"YTKACEFFmpeg" code:code
        userInfo:@{NSLocalizedDescriptionKey: message}];
}

static int YTKACEOpenInput(NSURL *URL, enum YTKACEFFmpegMediaType type,
                           AVFormatContext **context, int *streamIndex) {
    int result = avformat_open_input(context, URL.fileSystemRepresentation,
        NULL, NULL);
    if (result < 0) return result;
    result = avformat_find_stream_info(*context, NULL);
    if (result < 0) return result;
    result = av_find_best_stream(*context, type, -1, -1, NULL, 0);
    if (result < 0) return result;
    *streamIndex = result;
    return 0;
}

static int YTKACEReadPacket(AVFormatContext *context, int streamIndex,
                            AVPacket *packet) {
    int result = 0;
    while ((result = av_read_frame(context, packet)) >= 0) {
        if (packet->stream_index == streamIndex) return 0;
        av_packet_unref(packet);
    }
    return result;
}

static int64_t YTKACEPacketTime(AVPacket *packet, AVStream *stream) {
    int64_t value = packet->dts != AV_NOPTS_VALUE ? packet->dts : packet->pts;
    return value == AV_NOPTS_VALUE ? INT64_MAX :
        av_rescale_q(value, stream->time_base, AV_TIME_BASE_Q);
}

static int YTKACEWritePacket(AVFormatContext *output, AVPacket *packet,
                             AVStream *inputStream, AVStream *outputStream) {
    av_packet_rescale_ts(packet, inputStream->time_base, outputStream->time_base);
    packet->stream_index = outputStream->index;
    packet->pos = -1;
    int result = av_interleaved_write_frame(output, packet);
    av_packet_unref(packet);
    return result;
}

static NSError *YTKACERemux(NSURL *videoURL, NSURL *audioURL,
                            NSURL *outputURL) {
    AVFormatContext *video = NULL;
    AVFormatContext *audio = NULL;
    AVFormatContext *output = NULL;
    AVPacket *videoPacket = NULL;
    AVPacket *audioPacket = NULL;
    AVStream *videoInput = NULL;
    AVStream *audioInput = NULL;
    AVStream *videoOutput = NULL;
    AVStream *audioOutput = NULL;
    AVDictionary *options = NULL;
    int videoIndex = -1;
    int audioIndex = -1;
    BOOL hasVideo = NO;
    BOOL hasAudio = NO;
    NSString *stage = @"Open video";
    int result = YTKACEOpenInput(videoURL, AVMEDIA_TYPE_VIDEO, &video, &videoIndex);
    if (result < 0) goto cleanup;
    result = YTKACEOpenInput(audioURL, AVMEDIA_TYPE_AUDIO, &audio, &audioIndex);
    stage = @"Open audio";
    if (result < 0) goto cleanup;
    result = avformat_alloc_output_context2(&output, NULL, "mp4",
        outputURL.fileSystemRepresentation);
    stage = @"Create output";
    if (result < 0 || output == NULL) {
        if (result >= 0) result = AVERROR_UNKNOWN;
        goto cleanup;
    }
    videoInput = video->streams[videoIndex];
    audioInput = audio->streams[audioIndex];
    videoOutput = avformat_new_stream(output, NULL);
    audioOutput = avformat_new_stream(output, NULL);
    stage = @"Create tracks";
    if (videoOutput == NULL || audioOutput == NULL) {
        result = AVERROR(ENOMEM);
        goto cleanup;
    }
    result = avcodec_parameters_copy(videoOutput->codecpar, videoInput->codecpar);
    if (result < 0) goto cleanup;
    result = avcodec_parameters_copy(audioOutput->codecpar, audioInput->codecpar);
    if (result < 0) goto cleanup;
    videoOutput->codecpar->codec_tag = 0;
    audioOutput->codecpar->codec_tag = 0;
    videoOutput->time_base = videoInput->time_base;
    audioOutput->time_base = audioInput->time_base;
    if ((output->oformat->flags & AVFMT_NOFILE) == 0) {
        result = avio_open(&output->pb, outputURL.fileSystemRepresentation,
            AVIO_FLAG_WRITE);
        stage = @"Open output";
        if (result < 0) goto cleanup;
    }
    av_dict_set(&options, "movflags", "+faststart", 0);
    result = avformat_write_header(output, &options);
    stage = @"Write header";
    if (result < 0) goto cleanup;

    videoPacket = av_packet_alloc();
    audioPacket = av_packet_alloc();
    if (videoPacket == NULL || audioPacket == NULL) {
        result = AVERROR(ENOMEM);
        stage = @"Create packets";
        goto cleanup;
    }
    hasVideo = YTKACEReadPacket(video, videoIndex, videoPacket) >= 0;
    hasAudio = YTKACEReadPacket(audio, audioIndex, audioPacket) >= 0;
    while (hasVideo || hasAudio) {
        BOOL writeVideo = hasVideo;
        if (hasVideo && hasAudio) {
            writeVideo = YTKACEPacketTime(videoPacket, videoInput) <=
                YTKACEPacketTime(audioPacket, audioInput);
        }
        if (writeVideo) {
            result = YTKACEWritePacket(output, videoPacket, videoInput, videoOutput);
            stage = @"Write video";
            if (result < 0) goto cleanup;
            hasVideo = YTKACEReadPacket(video, videoIndex, videoPacket) >= 0;
        } else {
            result = YTKACEWritePacket(output, audioPacket, audioInput, audioOutput);
            stage = @"Write audio";
            if (result < 0) goto cleanup;
            hasAudio = YTKACEReadPacket(audio, audioIndex, audioPacket) >= 0;
        }
    }
    result = av_write_trailer(output);
    stage = @"Write trailer";

cleanup:
    av_dict_free(&options);
    av_packet_free(&videoPacket);
    av_packet_free(&audioPacket);
    avformat_close_input(&video);
    avformat_close_input(&audio);
    if (output != NULL) {
        if (output->pb != NULL) avio_closep(&output->pb);
        avformat_free_context(output);
    }
    return result < 0 ? YTKACEFFmpegError(result, stage) : nil;
}

static NSError *YTKACERemuxAudio(NSURL *audioURL, NSURL *outputURL) {
    AVFormatContext *audio = NULL;
    AVFormatContext *output = NULL;
    AVPacket *packet = NULL;
    AVStream *audioInput = NULL;
    AVStream *audioOutput = NULL;
    AVDictionary *options = NULL;
    int audioIndex = -1;
    NSString *stage = @"Open audio";
    int result = YTKACEOpenInput(audioURL, AVMEDIA_TYPE_AUDIO, &audio, &audioIndex);
    if (result < 0) goto cleanup;
    result = avformat_alloc_output_context2(&output, NULL, "mp4",
        outputURL.fileSystemRepresentation);
    stage = @"Create output";
    if (result < 0 || output == NULL) {
        if (result >= 0) result = AVERROR_UNKNOWN;
        goto cleanup;
    }
    audioInput = audio->streams[audioIndex];
    audioOutput = avformat_new_stream(output, NULL);
    stage = @"Create track";
    if (audioOutput == NULL) {
        result = AVERROR(ENOMEM);
        goto cleanup;
    }
    result = avcodec_parameters_copy(audioOutput->codecpar, audioInput->codecpar);
    if (result < 0) goto cleanup;
    audioOutput->codecpar->codec_tag = 0;
    audioOutput->time_base = audioInput->time_base;
    if ((output->oformat->flags & AVFMT_NOFILE) == 0) {
        result = avio_open(&output->pb, outputURL.fileSystemRepresentation,
            AVIO_FLAG_WRITE);
        stage = @"Open output";
        if (result < 0) goto cleanup;
    }
    av_dict_set(&options, "movflags", "+faststart", 0);
    result = avformat_write_header(output, &options);
    stage = @"Write header";
    if (result < 0) goto cleanup;
    packet = av_packet_alloc();
    if (packet == NULL) {
        result = AVERROR(ENOMEM);
        stage = @"Create packet";
        goto cleanup;
    }
    while ((result = YTKACEReadPacket(audio, audioIndex, packet)) >= 0) {
        result = YTKACEWritePacket(output, packet, audioInput, audioOutput);
        stage = @"Write audio";
        if (result < 0) goto cleanup;
    }
    if (result == AVERROR_EOF) result = 0;
    if (result < 0) goto cleanup;
    result = av_write_trailer(output);
    stage = @"Write trailer";

cleanup:
    av_dict_free(&options);
    av_packet_free(&packet);
    avformat_close_input(&audio);
    if (output != NULL) {
        if (output->pb != NULL) avio_closep(&output->pb);
        avformat_free_context(output);
    }
    return result < 0 ? YTKACEFFmpegError(result, stage) : nil;
}

@implementation YTKACEFFmpegMuxer

+ (void)remuxAudioURL:(NSURL *)audioURL
            outputURL:(NSURL *)outputURL
           completion:(YTKACEFFmpegCompletion)completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [NSFileManager.defaultManager removeItemAtURL:outputURL error:nil];
        av_log_set_level(AV_LOG_ERROR);
        NSError *error = YTKACERemuxAudio(audioURL, outputURL);
        dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
    });
}

+ (void)remuxVideoURL:(NSURL *)videoURL
             audioURL:(NSURL *)audioURL
            outputURL:(NSURL *)outputURL
           completion:(YTKACEFFmpegCompletion)completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [NSFileManager.defaultManager removeItemAtURL:outputURL error:nil];
        av_log_set_level(AV_LOG_ERROR);
        NSError *error = YTKACERemux(videoURL, audioURL, outputURL);
        dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
    });
}

+ (void)normalizeMediaURL:(NSURL *)mediaURL
                outputURL:(NSURL *)outputURL
               completion:(YTKACEFFmpegCompletion)completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [NSFileManager.defaultManager removeItemAtURL:outputURL error:nil];
        av_log_set_level(AV_LOG_ERROR);
        NSError *error = YTKACERemux(mediaURL, mediaURL, outputURL);
        dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
    });
}

+ (void)embedArtworkData:(NSData *)artworkData
                 mediaURL:(NSURL *)mediaURL
               completion:(YTKACEFFmpegCompletion)completion {
    if (artworkData.length == 0 || mediaURL == nil) {
        completion(YTKACEFFmpegError(AVERROR(EINVAL), @"Read artwork"));
        return;
    }
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:mediaURL options:nil];
    AVAssetExportSession *exporter = [[AVAssetExportSession alloc]
        initWithAsset:asset presetName:AVAssetExportPresetPassthrough];
    if (exporter == nil) {
        completion(YTKACEFFmpegError(AVERROR_UNKNOWN, @"Create artwork export"));
        return;
    }
    NSString *extension = mediaURL.pathExtension.lowercaseString;
    AVFileType outputType = [extension isEqualToString:@"m4a"]
        ? AVFileTypeAppleM4A : AVFileTypeMPEG4;
    if (![exporter.supportedFileTypes containsObject:outputType]) {
        completion(YTKACEFFmpegError(AVERROR(ENOTSUP), @"Embed artwork"));
        return;
    }
    NSURL *temporary = [mediaURL.URLByDeletingLastPathComponent
        URLByAppendingPathComponent:[NSString stringWithFormat:@".%@-artwork.%@",
            NSUUID.UUID.UUIDString, extension.length == 0 ? @"mp4" : extension]];
    [NSFileManager.defaultManager removeItemAtURL:temporary error:nil];
    AVMutableMetadataItem *artwork = [AVMutableMetadataItem metadataItem];
    artwork.identifier = AVMetadataCommonIdentifierArtwork;
    artwork.value = artworkData;
    artwork.dataType = @"com.apple.metadata.datatype.JPEG";
    NSMutableArray<AVMetadataItem *> *metadata = [asset.commonMetadata mutableCopy] ?:
        [NSMutableArray array];
    [metadata addObject:artwork];
    exporter.metadata = metadata;
    exporter.outputURL = temporary;
    exporter.outputFileType = outputType;
    exporter.shouldOptimizeForNetworkUse = YES;
    [exporter exportAsynchronouslyWithCompletionHandler:^{
        NSError *error = exporter.error;
        if (exporter.status == AVAssetExportSessionStatusCompleted) {
            NSFileManager *manager = NSFileManager.defaultManager;
            NSURL *backup = [mediaURL.URLByDeletingLastPathComponent
                URLByAppendingPathComponent:[@"." stringByAppendingString:
                    NSUUID.UUID.UUIDString]];
            if (![manager moveItemAtURL:mediaURL toURL:backup error:&error] ||
                ![manager moveItemAtURL:temporary toURL:mediaURL error:&error]) {
                if (![manager fileExistsAtPath:mediaURL.path]) {
                    [manager moveItemAtURL:backup toURL:mediaURL error:nil];
                }
            } else {
                [manager removeItemAtURL:backup error:nil];
            }
        }
        [NSFileManager.defaultManager removeItemAtURL:temporary error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
    }];
}

@end
