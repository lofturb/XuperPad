#import "XPDecoder.h"

#import "XPAudioOutput.h"
#import "XPConstants.h"

#import <libavcodec/avcodec.h>
#import <libavformat/avformat.h>
#import <libavutil/channel_layout.h>
#import <libavutil/opt.h>
#import <libswresample/swresample.h>
#import <libswscale/swscale.h>

typedef struct {
  AVFormatContext *format;
  AVCodecContext *video;
  AVCodecContext *audio;
  AVFrame *frame;
  AVPacket *packet;
  struct SwsContext *scale;
  SwrContext *resample;
  int videoIndex;
  int audioIndex;
  int width;
  int height;
  uint8_t *rgb;
  int rgbSize;
} XPFFmpegContext;

@interface XPVideoFrame : NSObject
@property (nonatomic, strong) NSData *rgb;
@property (nonatomic, assign) int width;
@property (nonatomic, assign) int height;
@property (nonatomic, assign) double pts;
@end

@implementation XPVideoFrame
@end

@interface XPDecoder () {
  XPFFmpegContext *state;
  NSString *streamAddress;
  NSDictionary *streamHeaders;
  NSMutableArray *frames;
  NSCondition *frameCondition;
  XPAudioOutput *audioOutput;
  volatile BOOL running;
  BOOL hasVideoStart;
  BOOL hasAudioStart;
  double videoStartPTS;
  double audioStartPTS;
  double videoWall;
}

- (void)decodeLoop;
- (void)presentLoop;
- (BOOL)openInput;
- (void)closeInput;
- (void)openAudioWithCodec:(const AVCodec *)audioCodec;
- (void)decodeVideoPacket;
- (void)decodeAudioPacket;
- (void)pushFrame:(XPVideoFrame *)frame;
- (XPVideoFrame *)nextFrameToShow;
- (void)throttleIfNeeded;
- (double)masterClock;
- (void)reportVideoSize:(int)width height:(int)height;
- (void)reportFailure:(NSString *)message;
- (void)reportEndOfStream;
- (void)broadcastFrames;

@end

static int XPInterruptCallback(void *opaque)
{
  XPDecoder *decoder = (__bridge XPDecoder *)opaque;
  if (decoder == nil) {
    return 1;
  }
  return decoder.isRunning ? 0 : 1;
}

@implementation XPDecoder

- (instancetype)init
{
  self = [super init];
  if (self != nil) {
    frames = [NSMutableArray array];
    frameCondition = [[NSCondition alloc] init];
    running = NO;
    state = NULL;
  }
  return self;
}

- (BOOL)isRunning
{
  return running;
}

- (BOOL)startWithAddress:(NSString *)address headers:(NSDictionary *)headers
{
  if (running) {
    return NO;
  }
  if (address.length == 0) {
    return NO;
  }
  streamAddress = [address copy];
  streamHeaders = [headers copy] ?: @{};
  frames = [NSMutableArray array];
  frameCondition = [[NSCondition alloc] init];
  hasVideoStart = NO;
  hasAudioStart = NO;
  videoStartPTS = 0;
  audioStartPTS = 0;
  videoWall = 0;
  running = YES;

  NSThread *worker = [[NSThread alloc] initWithTarget:self selector:@selector(decodeLoop) object:nil];
  worker.name = @"XuperPad.decode";
  [worker start];

  NSThread *presenter = [[NSThread alloc] initWithTarget:self selector:@selector(presentLoop) object:nil];
  presenter.name = @"XuperPad.present";
  [presenter start];

  return YES;
}

- (void)stop
{
  if (!running) {
    return;
  }
  running = NO;
  [self broadcastFrames];
  [audioOutput stop];
}

- (void)decodeLoop
{
  @autoreleasepool {
    if (![self openInput]) {
      [self closeInput];
      [self reportFailure:@"no se pudo abrir la direccion de video"];
      running = NO;
      [self broadcastFrames];
      return;
    }
    BOOL ended = NO;
    while (running) {
      [self throttleIfNeeded];
      if (!running) {
        break;
      }
      int result = av_read_frame(state->format, state->packet);
      if (result < 0) {
        ended = (result == AVERROR_EOF);
        break;
      }
      if (state->packet->stream_index == state->videoIndex) {
        [self decodeVideoPacket];
      } else if (state->packet->stream_index == state->audioIndex) {
        [self decodeAudioPacket];
      }
      av_packet_unref(state->packet);
    }
    BOOL cancelled = !running;
    [self closeInput];
    if (!cancelled) {
      if (ended) {
        [self reportEndOfStream];
      } else {
        [self reportFailure:@"la transmision de video se interrumpio"];
      }
    }
  }
}

- (void)presentLoop
{
  while (running) {
    @autoreleasepool {
      XPVideoFrame *frame = [self nextFrameToShow];
      if (frame == nil) {
        continue;
      }
      NSData *rgb = frame.rgb;
      int width = frame.width;
      int height = frame.height;
      dispatch_async(dispatch_get_main_queue(), ^{
        id<XPDecoderDelegate> delegate = self.delegate;
        if (delegate != nil) {
          [delegate decoder:self didProduceVideoFrame:rgb width:width height:height];
        }
      });
    }
  }
}

- (XPVideoFrame *)nextFrameToShow
{
  [frameCondition lock];
  while (running) {
    if (frames.count == 0) {
      [frameCondition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
      continue;
    }
    XPVideoFrame *head = frames.firstObject;
    double clock = [self masterClock];
    if (clock + 0.25 < head.pts) {
      [frameCondition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
      continue;
    }
    XPVideoFrame *chosen = head;
    while (frames.count > 1) {
      XPVideoFrame *candidate = frames[1];
      if (candidate.pts > clock + 0.25) {
        break;
      }
      chosen = candidate;
      [frames removeObjectAtIndex:0];
    }
    [frames removeObjectAtIndex:0];
    [frameCondition unlock];
    return chosen;
  }
  [frameCondition unlock];
  return nil;
}

- (double)masterClock
{
  if (hasAudioStart && audioOutput != nil) {
    return audioStartPTS + [audioOutput playedSeconds];
  }
  if (hasVideoStart) {
    return videoStartPTS + (CFAbsoluteTimeGetCurrent() - videoWall);
  }
  return 0;
}

- (void)throttleIfNeeded
{
  for (int guard = 0; guard < 300; guard++) {
    if (!running) {
      return;
    }
    BOOL audioBehind = (audioOutput != nil && [audioOutput queuedSeconds] > 1.2);
    BOOL videoBehind = NO;
    [frameCondition lock];
    videoBehind = frames.count > 8;
    [frameCondition unlock];
    if (!audioBehind && !videoBehind) {
      return;
    }
    [NSThread sleepForTimeInterval:0.01];
  }
}

- (BOOL)openInput
{
  state = calloc(1, sizeof(XPFFmpegContext));
  if (state == NULL) {
    return NO;
  }
  state->videoIndex = -1;
  state->audioIndex = -1;

  NSMutableString *headerText = [NSMutableString string];
  NSDictionary *entries = streamHeaders;
  BOOL hasUserAgent = NO;
  for (id key in entries) {
    id value = [entries objectForKey:key];
    if ([key isKindOfClass:[NSString class]] && [value isKindOfClass:[NSString class]]) {
      if ([(NSString *)key caseInsensitiveCompare:@"User-Agent"] == NSOrderedSame) {
        hasUserAgent = YES;
      }
      [headerText appendFormat:@"%@: %@\r\n", (NSString *)key, (NSString *)value];
    }
  }

  AVDictionary *options = NULL;
  if (headerText.length > 0) {
    av_dict_set(&options, "headers", [headerText UTF8String], 0);
  }
  if (!hasUserAgent) {
    av_dict_set(&options, "user_agent", [XPCdnUserAgent UTF8String], 0);
  }
  av_dict_set(&options, "timeout", "20000000", 0);
  av_dict_set(&options, "reconnect", "1", 0);
  av_dict_set(&options, "reconnect_streamed", "1", 0);

  AVFormatContext *format = avformat_alloc_context();
  if (format == NULL) {
    av_dict_free(&options);
    return NO;
  }
  format->interrupt_callback.opaque = (__bridge void *)self;
  format->interrupt_callback.callback = XPInterruptCallback;

  const char *url = [streamAddress UTF8String];
  int result = avformat_open_input(&format, url, NULL, &options);
  av_dict_free(&options);
  if (result < 0 || format == NULL) {
    return NO;
  }
  state->format = format;

  if (avformat_find_stream_info(format, NULL) < 0) {
    return NO;
  }

  AVCodec *videoCodec = NULL;
  state->videoIndex = av_find_best_stream(format, AVMEDIA_TYPE_VIDEO, -1, -1, &videoCodec, 0);
  if (state->videoIndex < 0 || videoCodec == NULL) {
    return NO;
  }
  AVCodecContext *videoContext = avcodec_alloc_context3(videoCodec);
  if (videoContext == NULL) {
    return NO;
  }
  if (avcodec_parameters_to_context(videoContext, format->streams[state->videoIndex]->codecpar) < 0) {
    avcodec_free_context(&videoContext);
    return NO;
  }
  videoContext->thread_count = 2;
  videoContext->thread_type = FF_THREAD_FRAME | FF_THREAD_SLICE;
  videoContext->flags2 |= AV_CODEC_FLAG2_FAST;
  if (avcodec_open2(videoContext, videoCodec, NULL) < 0) {
    avcodec_free_context(&videoContext);
    return NO;
  }
  state->video = videoContext;

  AVCodec *audioCodec = NULL;
  state->audioIndex = av_find_best_stream(format, AVMEDIA_TYPE_AUDIO, -1, -1, &audioCodec, 0);
  if (state->audioIndex >= 0 && audioCodec != NULL) {
    [self openAudioWithCodec:audioCodec];
  }

  state->frame = av_frame_alloc();
  state->packet = av_packet_alloc();
  if (state->frame == NULL || state->packet == NULL) {
    return NO;
  }
  return YES;
}

- (void)openAudioWithCodec:(const AVCodec *)audioCodec
{
  AVCodecContext *audioContext = avcodec_alloc_context3(audioCodec);
  if (audioContext == NULL) {
    return;
  }
  if (avcodec_parameters_to_context(audioContext, state->format->streams[state->audioIndex]->codecpar) < 0) {
    avcodec_free_context(&audioContext);
    return;
  }
  audioContext->thread_count = 1;
  if (avcodec_open2(audioContext, audioCodec, NULL) < 0) {
    avcodec_free_context(&audioContext);
    return;
  }
  state->audio = audioContext;

  int64_t inputLayout = audioContext->channel_layout;
  if (inputLayout == 0 && audioContext->channels > 0) {
    inputLayout = av_get_default_channel_layout(audioContext->channels);
  }
  if (inputLayout == 0) {
    return;
  }
  SwrContext *resample = swr_alloc();
  if (resample == NULL) {
    return;
  }
  av_opt_set_int(resample, "in_channel_layout", inputLayout, 0);
  av_opt_set_int(resample, "in_sample_rate", audioContext->sample_rate, 0);
  av_opt_set_int(resample, "out_channel_layout", AV_CH_LAYOUT_STEREO, 0);
  av_opt_set_int(resample, "out_sample_rate", 44100, 0);
  if (swr_init(resample) < 0) {
    swr_free(&resample);
    return;
  }
  state->resample = resample;

  XPAudioOutput *output = [[XPAudioOutput alloc] init];
  if ([output startWithSampleRate:44100 channels:2]) {
    audioOutput = output;
  }
}

- (void)decodeVideoPacket
{
  if (state->video == NULL) {
    return;
  }
  if (avcodec_send_packet(state->video, state->packet) < 0) {
    return;
  }
  while (avcodec_receive_frame(state->video, state->frame) == 0) {
    AVFrame *frame = state->frame;
    if (frame->width <= 0 || frame->height <= 0 || frame->format < 0) {
      av_frame_unref(frame);
      continue;
    }
    if (state->scale == NULL || state->width != frame->width || state->height != frame->height) {
      if (state->scale != NULL) {
        sws_freeContext(state->scale);
        state->scale = NULL;
      }
      state->scale = sws_getContext(frame->width,
                                    frame->height,
                                    (enum AVPixelFormat)frame->format,
                                    frame->width,
                                    frame->height,
                                    AV_PIX_FMT_RGB24,
                                    SWS_BILINEAR,
                                    NULL,
                                    NULL,
                                    NULL);
      if (state->scale == NULL) {
        av_frame_unref(frame);
        continue;
      }
      state->width = frame->width;
      state->height = frame->height;
      int size = frame->width * frame->height * 3;
      if (state->rgbSize < size) {
        if (state->rgb != NULL) {
          av_free(state->rgb);
          state->rgb = NULL;
          state->rgbSize = 0;
        }
        state->rgb = av_malloc((size_t)size);
        state->rgbSize = size;
      }
      [self reportVideoSize:frame->width height:frame->height];
    }
    if (state->rgb == NULL) {
      av_frame_unref(frame);
      continue;
    }
    uint8_t *destination[4] = { state->rgb, NULL, NULL, NULL };
    int strides[4] = { state->width * 3, 0, 0, 0 };
    const uint8_t *source[AV_NUM_DATA_POINTERS];
    for (int index = 0; index < AV_NUM_DATA_POINTERS; index++) {
      source[index] = frame->data[index];
    }
    sws_scale(state->scale, source, frame->linesize, 0, frame->height, destination, strides);

    double pts = (frame->pts == AV_NOPTS_VALUE) ? 0 : frame->pts * av_q2d(state->video->time_base);
    XPVideoFrame *output = [[XPVideoFrame alloc] init];
    output.rgb = [NSData dataWithBytes:state->rgb length:(NSUInteger)(state->width * state->height * 3)];
    output.width = state->width;
    output.height = state->height;
    output.pts = pts;
    [self pushFrame:output];
    av_frame_unref(frame);
  }
}

- (void)decodeAudioPacket
{
  if (state->audio == NULL || state->resample == NULL) {
    return;
  }
  if (avcodec_send_packet(state->audio, state->packet) < 0) {
    return;
  }
  while (avcodec_receive_frame(state->audio, state->frame) == 0) {
    AVFrame *frame = state->frame;
    int available = swr_get_out_samples(state->resample, frame->nb_samples);
    if (available > 0) {
      int bytes = available * 2 * (int)sizeof(int16_t);
      uint8_t *buffer = av_malloc((size_t)bytes);
      if (buffer != NULL) {
        uint8_t *destination = buffer;
        const uint8_t *source[AV_NUM_DATA_POINTERS];
        for (int index = 0; index < AV_NUM_DATA_POINTERS; index++) {
          source[index] = frame->extended_data[index];
        }
        int converted = swr_convert(state->resample,
                                    &destination,
                                    available,
                                    source,
                                    frame->nb_samples);
        if (converted > 0) {
          if (!hasAudioStart) {
            hasAudioStart = YES;
            audioStartPTS = (frame->pts == AV_NOPTS_VALUE)
                          ? 0
                          : frame->pts * av_q2d(state->audio->time_base);
          }
          NSData *pcm = [NSData dataWithBytes:buffer
                                       length:(NSUInteger)(converted * 2 * (int)sizeof(int16_t))];
          [audioOutput enqueuePCM:pcm];
        }
        av_free(buffer);
      }
    }
    av_frame_unref(frame);
  }
}

- (void)pushFrame:(XPVideoFrame *)frame
{
  if (!hasVideoStart) {
    hasVideoStart = YES;
    videoStartPTS = frame.pts;
    videoWall = CFAbsoluteTimeGetCurrent();
  }
  [frameCondition lock];
  [frames addObject:frame];
  while (frames.count > 16) {
    [frames removeObjectAtIndex:0];
  }
  [frameCondition unlock];
  [self broadcastFrames];
}

- (void)reportVideoSize:(int)width height:(int)height
{
  dispatch_async(dispatch_get_main_queue(), ^{
    id<XPDecoderDelegate> delegate = self.delegate;
    if (delegate != nil) {
      [delegate decoder:self didOpenVideoWithWidth:width height:height];
    }
  });
}

- (void)reportFailure:(NSString *)message
{
  dispatch_async(dispatch_get_main_queue(), ^{
    id<XPDecoderDelegate> delegate = self.delegate;
    if (delegate != nil) {
      [delegate decoder:self didFailWithMessage:message];
    }
  });
}

- (void)reportEndOfStream
{
  dispatch_async(dispatch_get_main_queue(), ^{
    id<XPDecoderDelegate> delegate = self.delegate;
    if (delegate != nil) {
      [delegate decoder:self didFinishWithMessage:@"El contenido ha terminado."];
    }
  });
}

- (void)broadcastFrames
{
  [frameCondition lock];
  [frameCondition broadcast];
  [frameCondition unlock];
}

- (void)closeInput
{
  if (state == NULL) {
    return;
  }
  if (state->packet != NULL) {
    av_packet_free(&state->packet);
  }
  if (state->frame != NULL) {
    av_frame_free(&state->frame);
  }
  if (state->scale != NULL) {
    sws_freeContext(state->scale);
    state->scale = NULL;
  }
  if (state->resample != NULL) {
    swr_free(&state->resample);
    state->resample = NULL;
  }
  if (state->video != NULL) {
    avcodec_free_context(&state->video);
    state->video = NULL;
  }
  if (state->audio != NULL) {
    avcodec_free_context(&state->audio);
    state->audio = NULL;
  }
  if (state->rgb != NULL) {
    av_free(state->rgb);
    state->rgb = NULL;
  }
  if (state->format != NULL) {
    avformat_close_input(&state->format);
    state->format = NULL;
  }
  free(state);
  state = NULL;
}

- (void)dealloc
{
  [self stop];
}

@end
