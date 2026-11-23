#import "XPDecoder.h"

#import "XPAudioOutput.h"
#import "XPConstants.h"

#import <libavcodec/avcodec.h>
#import <libavcodec/codec_desc.h>
#import <libavformat/avformat.h>
#import <libavformat/avio.h>
#import <libavutil/channel_layout.h>
#import <libavutil/dict.h>
#import <libavutil/error.h>
#import <libavutil/frame.h>
#import <libavutil/log.h>
#import <libswresample/swresample.h>
#import <libswscale/swscale.h>

#import <mach/mach.h>

#import <stdarg.h>
#import <stdint.h>
#import <stdio.h>
#import <string.h>
#import <math.h>

typedef struct {
  AVFormatContext *format;
  AVCodecContext *video;
  AVCodecContext *audio;
  AVCodecContext *subtitle;
  AVFrame *frame;
  AVPacket *packet;
  AVFrame *videoFrame;
  struct SwsContext *scale;
  SwrContext *resample;
  int videoIndex;
  int audioIndex;
  int subtitleIndex;
  int width;
  int height;
  uint8_t *rgb;
  int rgbSize;
  int audioSampleRate;
  int audioChannels;
  int64_t audioChannelLayout;
} XPFFmpegContext;

@interface XPQueuedPacket : NSObject
@property (nonatomic, assign) AVPacket *packet;
@property (nonatomic, assign) int64_t generation;
@end

@implementation XPQueuedPacket
@end

@implementation XPVideoFrameData

- (void)dealloc
{
  if (self.nativeFrame != NULL) {
    AVFrame *frame = (AVFrame *)self.nativeFrame;
    av_frame_free(&frame);
    self.nativeFrame = NULL;
  }
}

@end

@implementation XPTrackInfo
@end

@implementation XPSubtitleCue
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
  double audioOffset;
  double videoWall;
  NSString *failureDetail;
  NSUInteger videoPacketCount;
  NSUInteger audioPacketCount;
  NSUInteger subtitlePacketCount;
  NSUInteger frameCount;
  CFAbsoluteTime lastProgressAt;
  double readSeconds;
  double videoDecodeSeconds;
  double audioDecodeSeconds;
  double scaleSeconds;
  double copySeconds;
  double slowestReadSeconds;
  int64_t lastBytesRead;
  NSUInteger lastFrameCount;
  double lastReadSeconds;
  double lastVideoDecodeSeconds;
  double lastAudioDecodeSeconds;
  double lastScaleSeconds;
  double lastCopySeconds;
  double latestPTS;
  double demuxPTS;
  double audioDemuxPTS;
  double videoDemuxPTS;
  double videoMasterOffset;
  double lastVideoDecodePTS;
  NSUInteger videoSendErrorCount;
  NSUInteger videoReferenceErrorCount;
  NSUInteger videoKeyframeWaitCount;
  NSUInteger pictICount;
  NSUInteger pictPCount;
  NSUInteger pictBCount;
  NSUInteger pictOtherCount;
  double lastDeliverWall;
  double maxDeliverGap;
  NSUInteger bigDeliverGapCount;
  CFAbsoluteTime videoKeyframeWaitSince;
  BOOL videoNeedsKeyframe;
  double lastAudioClock;
  CFAbsoluteTime lastAudioClockAt;
  volatile BOOL audioClockHealthy;
  int pcmPeak;
  long long pcmSquareSum;
  long long pcmSampleCount;
  BOOL videoSizeReported;
  XPVideoFrameData *pendingFrame;
  BOOL pendingDeliveryScheduled;
  NSLock *clockLock;
  BOOL paused;
  CFAbsoluteTime pauseStartedAt;
  double frozenClock;
  double streamDuration;
  BOOL hasPendingSeek;
  double pendingSeekTime;
  BOOL directUploadActive;
  NSMutableArray *videoPackets;
  NSCondition *videoCondition;
  volatile int64_t videoGeneration;
  int64_t decodedVideoGeneration;
  BOOL videoThreadFinished;
  NSCondition *videoExitCondition;
  NSMutableArray *audioTracks;
  NSMutableArray *subtitleTracks;
  NSInteger selectedAudioIndex;
  NSInteger selectedSubtitleIndex;
  BOOL hasPendingAudioSelection;
  NSInteger pendingAudioIndex;
  BOOL hasPendingSubtitleSelection;
  NSInteger pendingSubtitleIndex;
  BOOL hasPendingRate;
  float pendingRate;
  float currentRate;
  NSMutableArray *subtitleCues;
  NSLock *subtitleLock;
  NSString *informationText;
  int outputSampleRate;
}

- (void)decodeLoop;
- (void)videoDecodeLoop;
- (void)presentLoop;
- (void)deliverPendingFrame;
- (BOOL)openInput;
- (void)closeInput;
- (void)openAudioForStreamIndex:(int)streamIndex;
- (void)closeAudioDecoder;
- (void)openSubtitleForStreamIndex:(int)streamIndex;
- (void)closeSubtitleDecoder;
- (void)decodeVideoPacket:(AVPacket *)packet generation:(int64_t)generation;
- (void)drainVideoFrames:(int64_t)generation;
- (void)decodeAudioPacket;
- (void)decodeSubtitlePacket;
- (void)enqueueVideoPacket;
- (XPQueuedPacket *)takeVideoPacket;
- (void)pushFrame:(XPVideoFrameData *)frame;
- (XPVideoFrameData *)nextFrameToShow;
- (XPVideoFrameData *)yuvFrameFromFrame:(AVFrame *)frame;
- (XPVideoFrameData *)rgbFrameFromFrame:(AVFrame *)frame;
- (void)throttleIfNeeded;
- (void)waitForVideoPace:(double)pts;
- (void)performPendingSeek;
- (void)applyPendingSelections;
- (void)throttleByTimestamp;
- (void)realignAudioClock;
- (NSUInteger)videoPacketsToDrop;
- (double)masterClock;
- (double)videoClock;
- (double)videoMasterOffsetValue;
- (void)updateClockHealth;
- (void)reportVideoSize:(int)width height:(int)height;
- (void)reportFailure:(NSString *)message;
- (void)reportEndOfStream;
- (void)broadcastFrames;
- (void)broadcastVideoPackets;
- (void)reportTracks;
- (void)setFailureDetail:(NSString *)detail;
- (void)markVideoThreadFinished;
- (void)rebuildInformationText;
- (double)packetTime:(AVPacket *)packet streamIndex:(int)streamIndex;
- (double)packetDecodeTime:(AVPacket *)packet streamIndex:(int)streamIndex;
- (void)resetAudioOutputWithRate:(int)rate;

@end

static NSString *XPFFmpegErrorText(int code)
{
  char buffer[AV_ERROR_MAX_STRING_SIZE];
  memset(buffer, 0, sizeof(buffer));
  av_strerror(code, buffer, sizeof(buffer));
  return [NSString stringWithUTF8String:buffer] ?: @"desconocido";
}

static const NSUInteger XPVideoQueueLimit = 36;
static const NSUInteger XPVideoPacketLimit = 480;
static const double XPDemuxLeadSeconds = 2.50;
static const double XPVideoLeadSeconds = 1.50;
static const double XPAudioQueueTargetSeconds = 1.00;
static const double XPVideoDiscontinuitySeconds = 1.00;
static const double XPVideoKeyframeWaitLimit = 8.00;
static const double XPVideoPresentationDelaySeconds = 0.30;

static double XPResidentMegabytes(void)
{
  mach_task_basic_info_data_t info;
  mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
  kern_return_t result = task_info(mach_task_self(),
                                   MACH_TASK_BASIC_INFO,
                                   (task_info_t)&info,
                                   &count);
  if (result != KERN_SUCCESS) {
    return 0.0;
  }
  return (double)info.resident_size / (1024.0 * 1024.0);
}

static NSData *XPCopyPlane(const uint8_t *source, int sourceStride, int width, int height)
{
  if (source == NULL || sourceStride <= 0 || width <= 0 || height <= 0) {
    return nil;
  }
  NSMutableData *result = [NSMutableData dataWithLength:(NSUInteger)((size_t)width * (size_t)height)];
  if (result == nil) {
    return nil;
  }
  uint8_t *target = (uint8_t *)result.mutableBytes;
  for (int row = 0; row < height; row++) {
    memcpy(target + (size_t)row * (size_t)width,
           source + (size_t)row * (size_t)sourceStride,
           (size_t)width);
  }
  return result;
}

static int XPInterruptCallback(void *opaque)
{
  XPDecoder *decoder = (__bridge XPDecoder *)opaque;
  if (decoder == nil) {
    return 1;
  }
  return decoder.isRunning ? 0 : 1;
}

static volatile BOOL XPFFmpegVerbose = NO;
static volatile BOOL XPFFmpegReferenceErrorPending = NO;

static void XPFFmpegLogCallback(void *context, int level, const char *format, va_list arguments)
{
  if (level == AV_LOG_DEBUG || level == AV_LOG_TRACE) {
    return;
  }
  if (level == AV_LOG_INFO && !XPFFmpegVerbose) {
    return;
  }
  if (level < AV_LOG_ERROR) {
    return;
  }
  char buffer[768];
  int printed = vsnprintf(buffer, sizeof(buffer), format, arguments);
  if (printed <= 0) {
    return;
  }
  if (strstr(buffer, "Could not find ref") != NULL) {
    XPFFmpegReferenceErrorPending = YES;
  }
  NSLog(@"[XuperPad] ffmpeg: %s", buffer);
}

static NSString *XPDictionaryValue(AVDictionary *dictionary, NSString *key)
{
  if (dictionary == NULL || key.length == 0) {
    return nil;
  }
  AVDictionaryEntry *entry = av_dict_get(dictionary, [key UTF8String], NULL, 0);
  if (entry == NULL || entry->value == NULL) {
    return nil;
  }
  return [NSString stringWithUTF8String:entry->value];
}

static NSString *XPLanguageName(NSString *code)
{
  if (code.length == 0) {
    return @"Sin idioma";
  }
  NSString *key = [[code substringToIndex:MIN((NSUInteger)3, code.length)] lowercaseString];
  NSDictionary *names = @{ @"spa" : @"Español",
                           @"eng" : @"Inglés",
                           @"jpn" : @"Japonés",
                           @"fra" : @"Francés",
                           @"fre" : @"Francés",
                           @"deu" : @"Alemán",
                           @"ger" : @"Alemán",
                           @"por" : @"Portugués",
                           @"ita" : @"Italiano",
                           @"rus" : @"Ruso",
                           @"zho" : @"Chino",
                           @"chi" : @"Chino",
                           @"kor" : @"Coreano",
                           @"ara" : @"Árabe",
                           @"hin" : @"Hindi",
                           @"tur" : @"Turco",
                           @"pol" : @"Polaco",
                           @"nld" : @"Neerlandés",
                           @"dut" : @"Neerlandés",
                           @"swe" : @"Sueco",
                           @"nor" : @"Noruego",
                           @"dan" : @"Danés",
                           @"fin" : @"Finés",
                           @"ces" : @"Checo",
                           @"cze" : @"Checo",
                           @"ell" : @"Griego",
                           @"gre" : @"Griego",
                           @"heb" : @"Hebreo",
                           @"hun" : @"Húngaro",
                           @"ron" : @"Rumano",
                           @"rum" : @"Rumano",
                           @"ukr" : @"Ucraniano",
                           @"vie" : @"Vietnamita",
                           @"tha" : @"Tailandés",
                           @"ind" : @"Indonesio",
                           @"msa" : @"Malayo",
                           @"may" : @"Malayo",
                           @"cat" : @"Catalán",
                           @"eus" : @"Euskera",
                           @"baq" : @"Euskera",
                           @"glg" : @"Gallego",
                           @"bul" : @"Búlgaro",
                           @"srp" : @"Serbio",
                           @"hrv" : @"Croata",
                           @"slv" : @"Esloveno",
                           @"slk" : @"Eslovaco",
                           @"lit" : @"Lituano",
                           @"lav" : @"Letón",
                           @"est" : @"Estonio",
                           @"mul" : @"Multilingüe",
                           @"und" : @"Sin idioma",
                           @"zxx" : @"Sin texto",
                           @"qaa" : @"Desconocido" };
  NSString *name = [names objectForKey:key];
  if (name != nil) {
    return name;
  }
  return code.uppercaseString;
}

static NSString *XPASSLineText(const char *ass)
{
  if (ass == NULL) {
    return nil;
  }
  NSString *line = [NSString stringWithUTF8String:ass];
  if (line.length == 0) {
    return nil;
  }
  NSArray *parts = [line componentsSeparatedByString:@","];
  if (parts.count < 10) {
    NSString *trimmed = [line stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return trimmed.length > 0 ? trimmed : nil;
  }
  NSMutableArray *tail = [NSMutableArray array];
  for (NSUInteger index = 9; index < parts.count; index++) {
    [tail addObject:[parts objectAtIndex:index]];
  }
  NSString *text = [tail componentsJoinedByString:@","];
  text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  text = [text stringByReplacingOccurrencesOfString:@"\\N" withString:@"\n"];
  text = [text stringByReplacingOccurrencesOfString:@"\\n" withString:@"\n"];
  text = [text stringByReplacingOccurrencesOfString:@"\\h" withString:@" "];
  return text.length > 0 ? text : nil;
}

@implementation XPDecoder

- (instancetype)init
{
  self = [super init];
  if (self != nil) {
    frames = [NSMutableArray array];
    frameCondition = [[NSCondition alloc] init];
    videoPackets = [NSMutableArray array];
    videoCondition = [[NSCondition alloc] init];
    videoExitCondition = [[NSCondition alloc] init];
    audioTracks = [NSMutableArray array];
    subtitleTracks = [NSMutableArray array];
    subtitleCues = [NSMutableArray array];
    subtitleLock = [[NSLock alloc] init];
    running = NO;
    state = NULL;
    failureDetail = nil;
    videoPacketCount = 0;
    audioPacketCount = 0;
    subtitlePacketCount = 0;
    frameCount = 0;
    lastProgressAt = 0;
    readSeconds = 0;
    videoDecodeSeconds = 0;
    audioDecodeSeconds = 0;
    scaleSeconds = 0;
    copySeconds = 0;
    slowestReadSeconds = 0;
    lastBytesRead = 0;
    lastFrameCount = 0;
    lastReadSeconds = 0;
    lastVideoDecodeSeconds = 0;
    lastAudioDecodeSeconds = 0;
    lastScaleSeconds = 0;
lastCopySeconds = 0;
    latestPTS = 0;
    demuxPTS = 0;
    videoMasterOffset = 0;
    lastVideoDecodePTS = 0;
    videoSendErrorCount = 0;
    videoReferenceErrorCount = 0;
    videoKeyframeWaitCount = 0;
    pictICount = 0;
    pictPCount = 0;
    pictBCount = 0;
    pictOtherCount = 0;
    lastDeliverWall = 0;
    maxDeliverGap = 0;
    bigDeliverGapCount = 0;
    videoKeyframeWaitSince = 0;
    lastAudioClock = 0;
    lastAudioClockAt = 0;
    audioClockHealthy = NO;
    pcmPeak = 0;
    pcmSquareSum = 0;
    pcmSampleCount = 0;
    videoSizeReported = NO;
    pendingFrame = nil;
    pendingDeliveryScheduled = NO;
    clockLock = [[NSLock alloc] init];
    paused = NO;
    pauseStartedAt = 0;
    frozenClock = 0;
    streamDuration = 0;
    hasPendingSeek = NO;
    pendingSeekTime = 0;
    directUploadActive = NO;
    videoGeneration = 0;
    decodedVideoGeneration = 0;
    videoThreadFinished = YES;
    selectedAudioIndex = -1;
    selectedSubtitleIndex = -1;
    hasPendingAudioSelection = NO;
    pendingAudioIndex = -1;
    hasPendingSubtitleSelection = NO;
    pendingSubtitleIndex = -1;
    hasPendingRate = NO;
    pendingRate = 1.0f;
    currentRate = 1.0f;
    informationText = @"";
    outputSampleRate = 0;
  }
  return self;
}

- (BOOL)isRunning
{
  return running;
}

- (NSArray *)audioTracks
{
  return [audioTracks copy];
}

- (NSArray *)subtitleTracks
{
  return [subtitleTracks copy];
}

- (NSInteger)selectedAudioTrackIndex
{
  return selectedAudioIndex;
}

- (NSInteger)selectedSubtitleTrackIndex
{
  return selectedSubtitleIndex;
}

- (NSString *)informationText
{
  return informationText ?: @"";
}

- (XPSubtitleCue *)activeSubtitle
{
  double clock = [self masterClock];
  if (clock <= 0.0) {
    return nil;
  }
  [subtitleLock lock];
  XPSubtitleCue *found = nil;
  NSMutableArray *expired = [NSMutableArray array];
  for (XPSubtitleCue *cue in subtitleCues) {
    if (cue.end < clock - 5.0) {
      [expired addObject:cue];
      continue;
    }
    if (clock >= cue.start && clock <= cue.end) {
      found = cue;
    }
  }
  if (expired.count > 0) {
    [subtitleCues removeObjectsInArray:expired];
  }
  [subtitleLock unlock];
  return found;
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
  videoPackets = [NSMutableArray array];
  videoCondition = [[NSCondition alloc] init];
  videoExitCondition = [[NSCondition alloc] init];
  audioTracks = [NSMutableArray array];
  subtitleTracks = [NSMutableArray array];
  subtitleCues = [NSMutableArray array];
  hasVideoStart = NO;
  hasAudioStart = NO;
  videoStartPTS = 0;
  audioStartPTS = 0;
  audioOffset = 0;
  videoWall = 0;
  failureDetail = nil;
  pictICount = 0;
  pictPCount = 0;
  pictBCount = 0;
  pictOtherCount = 0;
  lastDeliverWall = 0;
  maxDeliverGap = 0;
  bigDeliverGapCount = 0;
  videoPacketCount = 0;
  audioPacketCount = 0;
  subtitlePacketCount = 0;
  frameCount = 0;
  lastProgressAt = 0;
  readSeconds = 0;
  videoDecodeSeconds = 0;
  audioDecodeSeconds = 0;
  scaleSeconds = 0;
  copySeconds = 0;
  slowestReadSeconds = 0;
  lastBytesRead = 0;
  lastFrameCount = 0;
  lastReadSeconds = 0;
  lastVideoDecodeSeconds = 0;
  lastAudioDecodeSeconds = 0;
  lastScaleSeconds = 0;
  lastCopySeconds = 0;
  latestPTS = 0;
  demuxPTS = 0;
  lastAudioClock = 0;
  lastAudioClockAt = 0;
  audioClockHealthy = NO;
  pcmPeak = 0;
  pcmSquareSum = 0;
  pcmSampleCount = 0;
  videoSizeReported = NO;
  pendingFrame = nil;
  pendingDeliveryScheduled = NO;
  paused = NO;
  pauseStartedAt = 0;
  frozenClock = 0;
  streamDuration = 0;
  hasPendingSeek = NO;
  pendingSeekTime = 0;
  directUploadActive = NO;
  videoGeneration = 0;
  decodedVideoGeneration = 0;
  videoThreadFinished = YES;
  selectedAudioIndex = -1;
  selectedSubtitleIndex = -1;
  hasPendingAudioSelection = NO;
  pendingAudioIndex = -1;
  hasPendingSubtitleSelection = NO;
  pendingSubtitleIndex = -1;
  hasPendingRate = NO;
  currentRate = pendingRate > 0.0f ? pendingRate : 1.0f;
  informationText = @"";
  outputSampleRate = 0;
  running = YES;
  NSLog(@"[XuperPad] decodificador: inicio %@", address);

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
  [self broadcastVideoPackets];
  [audioOutput stop];
}

- (void)decodeLoop
{
  @autoreleasepool {
    lastProgressAt = CFAbsoluteTimeGetCurrent();
    XPFFmpegVerbose = YES;
    av_log_set_level(AV_LOG_INFO);
    av_log_set_callback(XPFFmpegLogCallback);
    if (![self openInput]) {
      [self closeInput];
      NSLog(@"[XuperPad] decodificador: fallo al abrir (%@)", failureDetail ?: @"sin detalle");
      [self reportFailure:@"no se pudo abrir la direccion de video"];
      running = NO;
      [self broadcastFrames];
      [self broadcastVideoPackets];
      return;
    }
    XPFFmpegVerbose = NO;

    videoThreadFinished = NO;
    NSThread *videoThread = [[NSThread alloc] initWithTarget:self
                                                     selector:@selector(videoDecodeLoop)
                                                       object:nil];
    videoThread.name = @"XuperPad.video";
    [videoThread start];

    BOOL ended = NO;
    while (running) {
      @autoreleasepool {
        [self applyPendingSelections];
        [self performPendingSeek];
        if (!running) {
          break;
        }
        if ([self isPaused]) {
          [NSThread sleepForTimeInterval:0.05];
          continue;
        }
        [self updateClockHealth];
        [self throttleIfNeeded];
        if (!running) {
          break;
        }
        CFAbsoluteTime readStart = CFAbsoluteTimeGetCurrent();
        int result = av_read_frame(state->format, state->packet);
        double readElapsed = CFAbsoluteTimeGetCurrent() - readStart;
        readSeconds += readElapsed;
        if (readElapsed > slowestReadSeconds) {
          slowestReadSeconds = readElapsed;
        }
        if (result < 0) {
          ended = (result == AVERROR_EOF);
          if (!ended) {
            NSLog(@"[XuperPad] decodificador: av_read_frame fallo %d %@",
                  result, XPFFmpegErrorText(result));
          }
          break;
        }
        int streamIndex = state->packet->stream_index;
        double packetTime = [self packetTime:state->packet streamIndex:streamIndex];
        if (packetTime > demuxPTS) {
          demuxPTS = packetTime;
        }
        if (streamIndex == state->videoIndex) {
          videoPacketCount++;
          videoDemuxPTS = packetTime;
          [self enqueueVideoPacket];
        } else if (streamIndex == state->audioIndex) {
          audioPacketCount++;
          audioDemuxPTS = packetTime;
          CFAbsoluteTime decodeStart = CFAbsoluteTimeGetCurrent();
          [self decodeAudioPacket];
          audioDecodeSeconds += CFAbsoluteTimeGetCurrent() - decodeStart;
        } else if (streamIndex == state->subtitleIndex) {
          subtitlePacketCount++;
          [self decodeSubtitlePacket];
        }
        av_packet_unref(state->packet);

        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (now - lastProgressAt >= 3.0) {
          double window = now - lastProgressAt;
          int64_t bytesRead = lastBytesRead;
          if (state->format != NULL && state->format->pb != NULL) {
            int64_t position = avio_tell(state->format->pb);
            if (position >= 0) {
              bytesRead = position;
            }
          }
          double bytesDelta = (double)(bytesRead - lastBytesRead);
          if (bytesDelta < 0) {
            bytesDelta = 0;
          }
          double framesDelta = (double)(frameCount - lastFrameCount);
          [frameCondition lock];
          NSUInteger queued = frames.count;
          [frameCondition unlock];
          [videoCondition lock];
          NSUInteger queuedPackets = videoPackets.count;
          [videoCondition unlock];
          double lag = latestPTS - [self masterClock];
          double playedSound = 0;
          double queuedSound = 0;
          NSUInteger audioCallbacks = 0;
          NSUInteger freeAudioBuffers = 0;
          float meterPeak = 0;
          float meterAverage = 0;
          if (audioOutput != nil) {
            playedSound = [audioOutput playedSeconds];
            queuedSound = [audioOutput queuedSeconds];
            audioCallbacks = [audioOutput callbackCount];
            freeAudioBuffers = [audioOutput freeBufferCount];
            meterPeak = [audioOutput meterPeak];
            meterAverage = [audioOutput meterAverage];
          }
          double rms = 0;
          if (pcmSampleCount > 0) {
            rms = sqrt((double)pcmSquareSum / (double)pcmSampleCount);
          }
          NSLog(@"[XuperPad] decodificador: progreso video %lu audio %lu subtitulos %lu fotogramas %lu imagenes %.2f/s red %.1f kB/s lectura %.2fs video %.2fs escala %.2fs copia %.2fs audio %.2fs leidos %.1f MB lectura maxima %.2fs cola %lu paquetes %lu retraso %.2fs sonido %.1fs en cola %.1fs libres %lu llamadas %lu pico %d rms %d medidor %.1f/%.1f memoria %.1f MB directo %d pista %ld refs %lu envios %lu esperas %lu tipos I %lu P %lu B %lu otros %lu hueco %.3fs huecos %lu",
                (unsigned long)videoPacketCount,
                (unsigned long)audioPacketCount,
                (unsigned long)subtitlePacketCount,
                (unsigned long)frameCount,
                framesDelta / window,
                bytesDelta / 1024.0 / window,
                readSeconds - lastReadSeconds,
                videoDecodeSeconds - lastVideoDecodeSeconds,
                scaleSeconds - lastScaleSeconds,
                copySeconds - lastCopySeconds,
                audioDecodeSeconds - lastAudioDecodeSeconds,
                (double)bytesRead / (1024.0 * 1024.0),
                slowestReadSeconds,
                (unsigned long)queued,
                (unsigned long)queuedPackets,
                lag,
                playedSound,
                queuedSound,
                (unsigned long)freeAudioBuffers,
                (unsigned long)audioCallbacks,
                pcmPeak,
                (int)rms,
                meterPeak,
                meterAverage,
                XPResidentMegabytes(),
                directUploadActive ? 1 : 0,
                (long)state->audioIndex,
                (unsigned long)videoReferenceErrorCount,
                (unsigned long)videoSendErrorCount,
                (unsigned long)videoKeyframeWaitCount,
                (unsigned long)pictICount,
                (unsigned long)pictPCount,
                (unsigned long)pictBCount,
                (unsigned long)pictOtherCount,
                maxDeliverGap,
                (unsigned long)bigDeliverGapCount);
          maxDeliverGap = 0;
          bigDeliverGapCount = 0;
          lastProgressAt = now;
          lastBytesRead = bytesRead;
          lastFrameCount = frameCount;
          lastReadSeconds = readSeconds;
          lastVideoDecodeSeconds = videoDecodeSeconds;
          lastAudioDecodeSeconds = audioDecodeSeconds;
          lastScaleSeconds = scaleSeconds;
          lastCopySeconds = copySeconds;
          pcmPeak = 0;
          pcmSquareSum = 0;
          pcmSampleCount = 0;
        }
      }
    }
    BOOL cancelled = !running;
    [self waitForVideoThread];
    [self closeInput];
    if (!cancelled) {
      if (ended) {
        NSLog(@"[XuperPad] decodificador: fin de la transmision");
        [self reportEndOfStream];
      } else {
        NSLog(@"[XuperPad] decodificador: transmision interrumpida");
        [self reportFailure:@"la transmision de video se interrumpio"];
      }
    }
  }
}

- (void)waitForVideoThread
{
  for (int guard = 0; guard < 300; guard++) {
    [videoExitCondition lock];
    BOOL finished = videoThreadFinished;
    [videoExitCondition unlock];
    if (finished) {
      return;
    }
    [NSThread sleepForTimeInterval:0.02];
  }
  NSLog(@"[XuperPad] decodificador: el hilo de video no termino a tiempo");
}

- (void)markVideoThreadFinished
{
  [videoExitCondition lock];
  videoThreadFinished = YES;
  [videoExitCondition broadcast];
  [videoExitCondition unlock];
}

- (void)videoDecodeLoop
{
  while (running) {
    @autoreleasepool {
      while (running && [self isPaused]) {
        [NSThread sleepForTimeInterval:0.02];
      }
      if (!running) {
        break;
      }
      XPQueuedPacket *item = [self takeVideoPacket];
      if (item == nil) {
        continue;
      }
      AVPacket *packet = item.packet;
      int64_t generation = item.generation;
      if (generation != decodedVideoGeneration) {
        decodedVideoGeneration = generation;
        if (state != NULL && state->video != NULL) {
          avcodec_flush_buffers(state->video);
        }
        lastVideoDecodePTS = 0;
      }
      BOOL isKey = packet != NULL && (packet->flags & AV_PKT_FLAG_KEY) != 0;
      [videoCondition lock];
      BOOL waitingForKey = videoNeedsKeyframe;
      [videoCondition unlock];
      if (waitingForKey) {
        if (!isKey) {
          if (videoKeyframeWaitSince == 0) {
            videoKeyframeWaitSince = CFAbsoluteTimeGetCurrent();
          }
          if (CFAbsoluteTimeGetCurrent() - videoKeyframeWaitSince < XPVideoKeyframeWaitLimit) {
            videoKeyframeWaitCount++;
            av_packet_free(&packet);
            continue;
          }
          NSLog(@"[XuperPad] decodificador: no llego una clave, se continua sin ella");
          [videoCondition lock];
          videoNeedsKeyframe = NO;
          [videoCondition unlock];
          videoKeyframeWaitSince = 0;
        } else {
          if (state != NULL && state->video != NULL) {
            avcodec_flush_buffers(state->video);
          }
          [videoCondition lock];
          videoNeedsKeyframe = NO;
          [videoCondition unlock];
          videoKeyframeWaitSince = 0;
          NSLog(@"[XuperPad] decodificador: la decodificacion se reanuda en una clave");
        }
      }
      int videoIndex = state != NULL ? state->videoIndex : -1;
      double decodeTime = [self packetDecodeTime:packet streamIndex:videoIndex];
      if (!isKey && lastVideoDecodePTS > 0 && decodeTime > 0 &&
          decodeTime + XPVideoDiscontinuitySeconds < lastVideoDecodePTS) {
        NSLog(@"[XuperPad] decodificador: salto de tiempo de video %.2fs, se reinicia el grupo",
              lastVideoDecodePTS - decodeTime);
        if (state != NULL && state->video != NULL) {
          avcodec_flush_buffers(state->video);
        }
        [videoCondition lock];
        videoNeedsKeyframe = YES;
        [videoCondition unlock];
        av_packet_free(&packet);
        continue;
      }
      if (decodeTime > lastVideoDecodePTS) {
        lastVideoDecodePTS = decodeTime;
      }
      [self decodeVideoPacket:packet generation:generation];
      if (XPFFmpegReferenceErrorPending) {
        XPFFmpegReferenceErrorPending = NO;
        videoReferenceErrorCount++;
        NSLog(@"[XuperPad] decodificador: falta una referencia de video, se espera una clave");
        if (state != NULL && state->video != NULL) {
          avcodec_flush_buffers(state->video);
        }
        [videoCondition lock];
        videoNeedsKeyframe = YES;
        [videoCondition unlock];
      }
      av_packet_free(&packet);
    }
  }
  [self markVideoThreadFinished];
}

- (void)enqueueVideoPacket
{
  if (state == NULL || state->packet == NULL) {
    return;
  }
  AVPacket *copy = av_packet_alloc();
  if (copy == NULL) {
    return;
  }
  if (av_packet_ref(copy, state->packet) < 0) {
    av_packet_free(&copy);
    return;
  }
  XPQueuedPacket *item = [[XPQueuedPacket alloc] init];
  item.packet = copy;
  item.generation = videoGeneration;
  [videoCondition lock];
  [videoPackets addObject:item];
  while (videoPackets.count > XPVideoPacketLimit) {
    NSUInteger removeCount = [self videoPacketsToDrop];
    if (removeCount == 0) {
      break;
    }
    for (NSUInteger index = 0; index < removeCount; index++) {
      XPQueuedPacket *dropped = [videoPackets firstObject];
      [videoPackets removeObjectAtIndex:0];
      AVPacket *droppedPacket = dropped.packet;
      if (droppedPacket != NULL) {
        av_packet_free(&droppedPacket);
      }
    }
    videoNeedsKeyframe = YES;
  }
  [videoCondition broadcast];
  [videoCondition unlock];
}

- (NSUInteger)videoPacketsToDrop
{
  NSUInteger firstKey = NSNotFound;
  for (NSUInteger index = 0; index < videoPackets.count; index++) {
    XPQueuedPacket *candidate = [videoPackets objectAtIndex:index];
    AVPacket *candidatePacket = candidate.packet;
    if (candidatePacket != NULL && (candidatePacket->flags & AV_PKT_FLAG_KEY) != 0) {
      firstKey = index;
      break;
    }
  }
  if (firstKey == NSNotFound) {
    videoNeedsKeyframe = YES;
    return videoPackets.count;
  }
  if (firstKey > 0) {
    return firstKey;
  }
  NSUInteger nextKey = NSNotFound;
  for (NSUInteger index = 1; index < videoPackets.count; index++) {
    XPQueuedPacket *candidate = [videoPackets objectAtIndex:index];
    AVPacket *candidatePacket = candidate.packet;
    if (candidatePacket != NULL && (candidatePacket->flags & AV_PKT_FLAG_KEY) != 0) {
      nextKey = index;
      break;
    }
  }
  if (nextKey == NSNotFound) {
    videoNeedsKeyframe = YES;
    return videoPackets.count;
  }
  return nextKey;
}

- (XPQueuedPacket *)takeVideoPacket
{
  [videoCondition lock];
  while (running && videoPackets.count == 0) {
    [videoCondition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
  }
  XPQueuedPacket *item = nil;
  if (videoPackets.count > 0) {
    item = [videoPackets firstObject];
    [videoPackets removeObjectAtIndex:0];
  }
  [videoCondition unlock];
  return item;
}

- (void)broadcastVideoPackets
{
  [videoCondition lock];
  [videoCondition broadcast];
  [videoCondition unlock];
}

- (void)presentLoop
{
  while (running) {
    @autoreleasepool {
      XPVideoFrameData *frame = [self nextFrameToShow];
      if (frame == nil) {
        continue;
      }
      [frameCondition lock];
      if (pendingFrame != nil) {
        XPVideoFrameData *dropped = pendingFrame;
        pendingFrame = nil;
        dropped = nil;
      }
      pendingFrame = frame;
      BOOL schedule = !pendingDeliveryScheduled;
      if (schedule) {
        pendingDeliveryScheduled = YES;
      }
      [frameCondition unlock];
      if (schedule) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self deliverPendingFrame];
        });
      }
    }
  }
}

- (void)deliverPendingFrame
{
  [frameCondition lock];
  XPVideoFrameData *frame = pendingFrame;
  pendingFrame = nil;
  pendingDeliveryScheduled = NO;
  [frameCondition unlock];

  if (frame == nil) {
    return;
  }
  double deliverWall = CFAbsoluteTimeGetCurrent();
  if (lastDeliverWall > 0) {
    double gap = deliverWall - lastDeliverWall;
    if (gap > maxDeliverGap) {
      maxDeliverGap = gap;
    }
    if (gap > 0.12) {
      bigDeliverGapCount++;
      NSLog(@"[XuperPad] decodificador: hueco de presentacion %.3fs pts %.2f", gap, frame.pts);
    }
  }
  lastDeliverWall = deliverWall;
  id<XPDecoderDelegate> delegate = self.delegate;
  if (delegate != nil) {
    [delegate decoder:self didProduceVideoFrame:frame];
  }
}

- (XPVideoFrameData *)nextFrameToShow
{
  [frameCondition lock];
  while (running) {
    if (frames.count == 0) {
      [frameCondition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
      continue;
    }
    double clock = [self masterClock];
    double offset = [self videoMasterOffsetValue] + XPVideoPresentationDelaySeconds;
    XPVideoFrameData *head = frames.firstObject;
    XPVideoFrameData *newest = frames.lastObject;
    if (newest.pts + offset < clock - 0.35) {
      [frames removeAllObjects];
      [frameCondition unlock];
      return newest;
    }
    if (head.pts + offset > clock + 0.05) {
      [frameCondition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
      continue;
    }
    XPVideoFrameData *chosen = head;
    NSUInteger chosenIndex = 0;
    for (NSUInteger index = 1; index < frames.count; index++) {
      XPVideoFrameData *candidate = frames[index];
      if (candidate.pts + offset > clock + 0.05) {
        break;
      }
      chosen = candidate;
      chosenIndex = index;
    }
    [frames removeObjectsInRange:NSMakeRange(0, chosenIndex + 1)];
    [frameCondition unlock];
    return chosen;
  }
  [frameCondition unlock];
  return nil;
}

- (double)masterClock
{
  [clockLock lock];
  if (paused) {
    double frozen = frozenClock;
    [clockLock unlock];
    return frozen;
  }
  BOOL audioReady = hasAudioStart && audioOutput != nil && audioClockHealthy;
  double start = audioReady ? audioStartPTS : 0.0;
  double offset = audioOffset;
  double rate = (double)currentRate;
  BOOL videoReady = hasVideoStart;
  double videoStart = videoStartPTS;
  double wall = videoWall;
  [clockLock unlock];

  if (audioReady) {
    return start + offset + [audioOutput playedSeconds] * rate;
  }
  if (videoReady) {
    return videoStart + (CFAbsoluteTimeGetCurrent() - wall) * rate;
  }
  return 0.0;
}

- (double)videoClock
{
  [clockLock lock];
  BOOL ready = hasVideoStart;
  double start = videoStartPTS;
  double wall = videoWall;
  double rate = (double)currentRate;
  [clockLock unlock];
  if (!ready) {
    return 0.0;
  }
  return start + (CFAbsoluteTimeGetCurrent() - wall) * rate;
}

- (double)videoMasterOffsetValue
{
  [clockLock lock];
  double value = videoMasterOffset;
  [clockLock unlock];
  return value;
}

- (BOOL)isPaused
{
  [clockLock lock];
  BOOL value = paused;
  [clockLock unlock];
  return value;
}

- (void)setPaused:(BOOL)value
{
  if ([self isPaused] == value) {
    return;
  }
  double current = [self masterClock];
  CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
  [clockLock lock];
  paused = value;
  if (value) {
    frozenClock = current;
    pauseStartedAt = now;
  } else {
    videoWall += now - pauseStartedAt;
  }
  [clockLock unlock];
  [audioOutput setPaused:value];
  NSLog(@"[XuperPad] decodificador: %@", value ? @"pausa" : @"reanudacion");
}

- (double)duration
{
  [clockLock lock];
  double value = streamDuration;
  [clockLock unlock];
  return value;
}

- (double)currentTime
{
  double clock = [self masterClock];
  [clockLock lock];
  double start = videoStartPTS + videoMasterOffset;
  [clockLock unlock];
  double value = clock - start;
  if (value < 0) {
    value = 0;
  }
  return value;
}

- (BOOL)seekToTime:(double)seconds
{
  if (!running) {
    return NO;
  }
  if (seconds < 0) {
    seconds = 0;
  }
  [clockLock lock];
  pendingSeekTime = seconds;
  hasPendingSeek = YES;
  [clockLock unlock];
  return YES;
}

- (BOOL)selectAudioTrack:(NSInteger)streamIndex
{
  if (!running) {
    return NO;
  }
  [clockLock lock];
  pendingAudioIndex = streamIndex;
  hasPendingAudioSelection = YES;
  [clockLock unlock];
  return YES;
}

- (BOOL)selectSubtitleTrack:(NSInteger)streamIndex
{
  if (!running) {
    return NO;
  }
  [clockLock lock];
  pendingSubtitleIndex = streamIndex;
  hasPendingSubtitleSelection = YES;
  [clockLock unlock];
  return YES;
}

- (void)setPlaybackRate:(float)rate
{
  if (rate < 0.25f) {
    rate = 0.25f;
  }
  if (rate > 4.0f) {
    rate = 4.0f;
  }
  [clockLock lock];
  pendingRate = rate;
  hasPendingRate = YES;
  [clockLock unlock];
}

- (float)playbackRate
{
  [clockLock lock];
  float rate = currentRate;
  [clockLock unlock];
  return rate;
}

- (void)applyPendingSelections
{
  [clockLock lock];
  BOOL wantsAudio = hasPendingAudioSelection;
  NSInteger audioIndex = pendingAudioIndex;
  hasPendingAudioSelection = NO;
  BOOL wantsSubtitle = hasPendingSubtitleSelection;
  NSInteger subtitleIndex = pendingSubtitleIndex;
  hasPendingSubtitleSelection = NO;
  BOOL wantsRate = hasPendingRate;
  float rate = pendingRate;
  hasPendingRate = NO;
  [clockLock unlock];

  if (wantsAudio && state != NULL) {
    if (audioIndex != state->audioIndex) {
      [self closeAudioDecoder];
      state->audioIndex = -1;
      selectedAudioIndex = -1;
      if (audioIndex >= 0 && audioIndex < (NSInteger)state->format->nb_streams) {
        [self openAudioForStreamIndex:(int)audioIndex];
      }
      [self reportTracks];
    }
  }

  if (wantsSubtitle && state != NULL) {
    if (subtitleIndex != state->subtitleIndex) {
      [self closeSubtitleDecoder];
      state->subtitleIndex = -1;
      selectedSubtitleIndex = -1;
      [subtitleLock lock];
      [subtitleCues removeAllObjects];
      [subtitleLock unlock];
      if (subtitleIndex >= 0 && subtitleIndex < (NSInteger)state->format->nb_streams) {
        [self openSubtitleForStreamIndex:(int)subtitleIndex];
      }
      [self reportTracks];
    }
  }

  if (wantsRate && state != NULL && state->audio != NULL) {
    [self applyRate:rate];
  }
}

- (void)applyRate:(float)rate
{
  if (state == NULL || state->audio == NULL || state->resample == NULL) {
    [clockLock lock];
    currentRate = rate;
    [clockLock unlock];
    return;
  }
  int sourceRate = state->audioSampleRate > 0 ? state->audioSampleRate : 44100;
  int targetRate = (int)((double)sourceRate * (double)rate);
  if (targetRate < 8000) {
    targetRate = 8000;
  }
  int64_t layout = state->audioChannelLayout;
  if (layout == 0 && state->audioChannels > 0) {
    layout = av_get_default_channel_layout(state->audioChannels);
  }
  SwrContext *resample = swr_alloc_set_opts(NULL,
                                             AV_CH_LAYOUT_STEREO,
                                             AV_SAMPLE_FMT_S16,
                                             targetRate,
                                             layout,
                                             (enum AVSampleFormat)state->audio->sample_fmt,
                                             state->audio->sample_rate,
                                             0,
                                             NULL);
  if (resample == NULL) {
    NSLog(@"[XuperPad] decodificador: no se pudo crear el remuestreador a %.2fx", rate);
    return;
  }
  if (swr_init(resample) < 0) {
    swr_free(&resample);
    NSLog(@"[XuperPad] decodificador: no se pudo iniciar el remuestreador a %.2fx", rate);
    return;
  }
  swr_free(&state->resample);
  state->resample = resample;
  [self resetAudioOutputWithRate:targetRate];
  [clockLock lock];
  currentRate = rate;
  [clockLock unlock];
  NSLog(@"[XuperPad] decodificador: velocidad %.2fx con salida %d Hz", rate, targetRate);
  [self reportTracks];
}

- (void)resetAudioOutputWithRate:(int)rate
{
  if (audioOutput == nil) {
    outputSampleRate = rate;
    return;
  }
  double before = [self masterClock];
  if (![audioOutput resetWithSampleRate:rate channels:2]) {
    NSLog(@"[XuperPad] decodificador: no se pudo reiniciar la salida de audio");
    return;
  }
  outputSampleRate = rate;
  [clockLock lock];
  if (hasAudioStart) {
    audioOffset = before - audioStartPTS;
  }
  lastAudioClock = 0;
  lastAudioClockAt = CFAbsoluteTimeGetCurrent();
  audioClockHealthy = hasAudioStart;
  [clockLock unlock];
}

- (void)performPendingSeek
{
  [clockLock lock];
  BOOL wanted = hasPendingSeek;
  double target = pendingSeekTime;
  hasPendingSeek = NO;
  [clockLock unlock];

  if (!wanted) {
    return;
  }
  if (state == NULL || state->format == NULL) {
    return;
  }
  int64_t position = (int64_t)(target * (double)AV_TIME_BASE);
  int result = av_seek_frame(state->format, -1, position, AVSEEK_FLAG_BACKWARD);
  if (result < 0) {
    NSLog(@"[XuperPad] decodificador: no se pudo buscar a %.1fs (%d %@)",
          target, result, XPFFmpegErrorText(result));
    return;
  }
  if (state->audio != NULL) {
    avcodec_flush_buffers(state->audio);
  }
  if (state->subtitle != NULL) {
    avcodec_flush_buffers(state->subtitle);
  }
  videoGeneration++;
  [videoCondition lock];
  for (XPQueuedPacket *item in videoPackets) {
    AVPacket *queuedPacket = item.packet;
    if (queuedPacket != NULL) {
      av_packet_free(&queuedPacket);
    }
  }
  [videoPackets removeAllObjects];
  [videoCondition broadcast];
  [videoCondition unlock];
  [frameCondition lock];
  [frames removeAllObjects];
  [frameCondition unlock];
  if (audioOutput != nil) {
    [audioOutput resetWithSampleRate:outputSampleRate > 0 ? outputSampleRate : 44100 channels:2];
  }
  [subtitleLock lock];
  [subtitleCues removeAllObjects];
  [subtitleLock unlock];
  [clockLock lock];
  hasVideoStart = NO;
  hasAudioStart = NO;
  videoStartPTS = 0;
  audioStartPTS = 0;
  audioOffset = 0;
  latestPTS = 0;
  demuxPTS = 0;
  lastAudioClock = 0;
  lastAudioClockAt = CFAbsoluteTimeGetCurrent();
  audioClockHealthy = NO;
  videoWall = CFAbsoluteTimeGetCurrent();
  [clockLock unlock];
  NSLog(@"[XuperPad] decodificador: busqueda aplicada en %.1fs", target);
}

- (void)updateClockHealth
{
  if ([self isPaused]) {
    return;
  }
  if (!hasAudioStart || audioOutput == nil) {
    audioClockHealthy = NO;
    return;
  }
  double played = [audioOutput playedSeconds];
  CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
  if (played > lastAudioClock + 0.001) {
    BOOL wasHealthy = audioClockHealthy;
    lastAudioClock = played;
    lastAudioClockAt = now;
    audioClockHealthy = YES;
    if (!wasHealthy) {
      [self realignAudioClock];
    }
    return;
  }
  if (lastAudioClockAt > 0 && now - lastAudioClockAt > 1.5) {
    audioClockHealthy = NO;
  }
}

- (void)realignAudioClock
{
  [clockLock lock];
  if (hasVideoStart) {
    double videoClock = videoStartPTS
                      + (CFAbsoluteTimeGetCurrent() - videoWall) * (double)currentRate
                      + videoMasterOffset;
    double audioClock = audioStartPTS + audioOffset + lastAudioClock * (double)currentRate;
    double delta = videoClock - audioClock;
    if (delta > 0.05 || delta < -0.05) {
      audioOffset += delta;
      NSLog(@"[XuperPad] decodificador: audio realineado %.2fs", delta);
    }
  }
  [clockLock unlock];
}

- (void)throttleIfNeeded
{
  if (state == NULL || audioOutput == nil || state->audio == NULL || state->audioIndex < 0) {
    [self throttleByTimestamp];
    return;
  }
  for (int guard = 0; guard < 400; guard++) {
    if (!running) {
      return;
    }
    [self updateClockHealth];
    double queued = [audioOutput queuedSeconds];
    if (queued < XPAudioQueueTargetSeconds) {
      return;
    }
    [NSThread sleepForTimeInterval:0.005];
  }
}

- (void)throttleByTimestamp
{
  for (int guard = 0; guard < 200; guard++) {
    if (!running) {
      return;
    }
    double clock = [self masterClock];
    if (clock <= 0 || demuxPTS <= 0) {
      return;
    }
    double lag = demuxPTS - clock;
    if (lag <= XPDemuxLeadSeconds) {
      return;
    }
    if (lag > 4.0) {
      return;
    }
    [NSThread sleepForTimeInterval:0.005];
  }
}

- (void)waitForVideoPace:(double)pts
{
  if (pts <= 0) {
    return;
  }
  for (int guard = 0; guard < 400; guard++) {
    if (!running) {
      return;
    }
    double clock = [self videoClock];
    if (clock <= 0) {
      return;
    }
    if (pts <= clock + XPVideoLeadSeconds) {
      return;
    }
    [NSThread sleepForTimeInterval:0.005];
  }
}

- (BOOL)openInput
{
  state = calloc(1, sizeof(XPFFmpegContext));
  if (state == NULL) {
    [self setFailureDetail:@"sin memoria para el contexto de FFmpeg"];
    return NO;
  }
  state->videoIndex = -1;
  state->audioIndex = -1;
  state->subtitleIndex = -1;
  CFAbsoluteTime openStart = CFAbsoluteTimeGetCurrent();

  NSMutableString *headerText = [NSMutableString string];
  NSDictionary *entries = streamHeaders;
  BOOL hasUserAgent = NO;
  for (id key in entries) {
    id value = [entries objectForKey:key];
    if ([key isKindOfClass:[NSString class]] && [value isKindOfClass:[NSString class]]) {
      if ([(NSString *)key caseInsensitiveCompare:@"User-Agent"] == NSOrderedSame) {
        hasUserAgent = YES;
      }
      NSLog(@"[XuperPad] decodificador: cabecera %@ de %lu bytes",
            (NSString *)key, (unsigned long)[(NSString *)value length]);
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
    [self setFailureDetail:@"sin memoria para el formato de FFmpeg"];
    return NO;
  }
  format->interrupt_callback.opaque = (__bridge void *)self;
  format->interrupt_callback.callback = XPInterruptCallback;

  const char *url = [streamAddress UTF8String];
  int result = avformat_open_input(&format, url, NULL, &options);
  av_dict_free(&options);
  if (result < 0 || format == NULL) {
    [self setFailureDetail:[NSString stringWithFormat:@"avformat_open_input %d %@",
                              result, XPFFmpegErrorText(result)]];
    return NO;
  }
  state->format = format;

  if (avformat_find_stream_info(format, NULL) < 0) {
    [self setFailureDetail:@"avformat_find_stream_info no pudo leer el flujo"];
    return NO;
  }

  NSString *formatName = format->iformat->name != NULL
                           ? [NSString stringWithUTF8String:format->iformat->name]
                           : @"desconocido";
  NSLog(@"[XuperPad] decodificador: formato %@ duracion %.1fs apertura %.2fs",
        formatName,
        format->duration / (double)AV_TIME_BASE,
        CFAbsoluteTimeGetCurrent() - openStart);
  [clockLock lock];
  streamDuration = format->duration > 0
    ? (double)format->duration / (double)AV_TIME_BASE
    : 0;
  [clockLock unlock];

  AVCodec *videoCodec = NULL;
  state->videoIndex = av_find_best_stream(format, AVMEDIA_TYPE_VIDEO, -1, -1, &videoCodec, 0);
  if (state->videoIndex < 0 || videoCodec == NULL) {
    [self setFailureDetail:@"el flujo no tiene pista de video"];
    return NO;
  }
  AVCodecContext *videoContext = avcodec_alloc_context3(videoCodec);
  if (videoContext == NULL) {
    [self setFailureDetail:@"sin memoria para el decodificador de video"];
    return NO;
  }
  if (avcodec_parameters_to_context(videoContext, format->streams[state->videoIndex]->codecpar) < 0) {
    avcodec_free_context(&videoContext);
    [self setFailureDetail:@"no se pudieron copiar los parametros de video"];
    return NO;
  }
  videoContext->pkt_timebase = format->streams[state->videoIndex]->time_base;
  videoContext->thread_count = 4;
  if (videoCodec->id == AV_CODEC_ID_HEVC) {
    videoContext->thread_type = FF_THREAD_FRAME;
    videoContext->skip_loop_filter = AVDISCARD_ALL;
    videoContext->flags2 |= AV_CODEC_FLAG2_FAST;
  } else {
    videoContext->thread_type = FF_THREAD_FRAME | FF_THREAD_SLICE;
  }
  if (avcodec_open2(videoContext, videoCodec, NULL) < 0) {
    avcodec_free_context(&videoContext);
    [self setFailureDetail:@"no se pudo abrir el decodificador de video"];
    return NO;
  }
  state->video = videoContext;
  NSString *videoCodecName = videoCodec->name != NULL
                               ? [NSString stringWithUTF8String:videoCodec->name]
                               : @"desconocido";
  NSLog(@"[XuperPad] decodificador: video %@ %dx%d pix %d bitrate %lld hilos %d filtro %d base %d/%d",
        videoCodecName,
        videoContext->width,
        videoContext->height,
        (int)videoContext->pix_fmt,
        (long long)videoContext->bit_rate,
        videoContext->thread_count,
        (int)videoContext->skip_loop_filter,
        videoContext->pkt_timebase.num,
        videoContext->pkt_timebase.den);

  [self enumerateTracks];

  AVCodec *audioCodec = NULL;
  int bestAudio = av_find_best_stream(format, AVMEDIA_TYPE_AUDIO, -1, -1, &audioCodec, 0);
  NSInteger chosenAudio = -1;
  for (XPTrackInfo *track in audioTracks) {
    if (track.original) {
      chosenAudio = track.streamIndex;
      break;
    }
  }
  if (chosenAudio < 0 && bestAudio >= 0) {
    chosenAudio = bestAudio;
  }
  if (chosenAudio >= 0) {
    [self openAudioForStreamIndex:(int)chosenAudio];
  }

  state->frame = av_frame_alloc();
  state->packet = av_packet_alloc();
  state->videoFrame = av_frame_alloc();
  if (state->frame == NULL || state->packet == NULL || state->videoFrame == NULL) {
    [self setFailureDetail:@"sin memoria para fotogramas y paquetes"];
    return NO;
  }
  [self rebuildInformationText];
  [self reportTracks];
  return YES;
}

- (void)enumerateTracks
{
  [audioTracks removeAllObjects];
  [subtitleTracks removeAllObjects];
  if (state == NULL || state->format == NULL) {
    return;
  }
  AVFormatContext *format = state->format;
  for (unsigned int index = 0; index < format->nb_streams; index++) {
    AVStream *stream = format->streams[index];
    if (stream == NULL || stream->codecpar == NULL) {
      continue;
    }
    if (stream->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
      XPTrackInfo *track = [self trackInfoForStream:stream];
      track.original = (stream->disposition & AV_DISPOSITION_DEFAULT) != 0;
      AVCodec *codec = avcodec_find_decoder(stream->codecpar->codec_id);
      track.available = (codec != NULL);
      [audioTracks addObject:track];
      NSLog(@"[XuperPad] decodificador: pista de audio %ld idioma %@ nombre %@ codec %@ original %d",
            (long)stream->index,
            track.languageCode.length > 0 ? track.languageCode : @"---",
            track.languageName,
            track.codecName,
            track.original ? 1 : 0);
      continue;
    }
    if (stream->codecpar->codec_type == AVMEDIA_TYPE_SUBTITLE) {
      XPTrackInfo *track = [self trackInfoForStream:stream];
      AVCodec *codec = avcodec_find_decoder(stream->codecpar->codec_id);
      track.available = (codec != NULL);
      [subtitleTracks addObject:track];
      NSLog(@"[XuperPad] decodificador: pista de subtitulos %ld idioma %@ nombre %@ codec %@ disponible %d",
            (long)stream->index,
            track.languageCode.length > 0 ? track.languageCode : @"---",
            track.languageName,
            track.codecName,
            track.available ? 1 : 0);
    }
  }
}

- (XPTrackInfo *)trackInfoForStream:(AVStream *)stream
{
  XPTrackInfo *track = [[XPTrackInfo alloc] init];
  track.streamIndex = (NSInteger)stream->index;
  NSString *language = XPDictionaryValue(stream->metadata, @"language");
  if (language.length > 0) {
    NSArray *parts = [language componentsSeparatedByString:@","];
    NSString *first = [[parts firstObject] stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    track.languageCode = [first lowercaseString];
  }
  track.languageName = XPLanguageName(track.languageCode);
  NSString *title = XPDictionaryValue(stream->metadata, @"title");
  track.title = title.length > 0 ? title : @"";
  const AVCodecDescriptor *descriptor = avcodec_descriptor_get(stream->codecpar->codec_id);
  if (descriptor != NULL && descriptor->name != NULL) {
    track.codecName = [NSString stringWithUTF8String:descriptor->name];
  } else {
    track.codecName = @"desconocido";
  }
  return track;
}

- (void)openAudioForStreamIndex:(int)streamIndex
{
  if (state == NULL || state->format == NULL) {
    return;
  }
  if (streamIndex < 0 || streamIndex >= (int)state->format->nb_streams) {
    return;
  }
  AVStream *stream = state->format->streams[streamIndex];
  if (stream == NULL || stream->codecpar == NULL) {
    return;
  }
  AVCodec *audioCodec = avcodec_find_decoder(stream->codecpar->codec_id);
  if (audioCodec == NULL) {
    NSLog(@"[XuperPad] decodificador: la pista de audio %ld no tiene decodificador", (long)streamIndex);
    return;
  }
  AVCodecContext *audioContext = avcodec_alloc_context3(audioCodec);
  if (audioContext == NULL) {
    return;
  }
  if (avcodec_parameters_to_context(audioContext, stream->codecpar) < 0) {
    avcodec_free_context(&audioContext);
    return;
  }
  audioContext->pkt_timebase = stream->time_base;
  audioContext->thread_count = 1;
  if (avcodec_open2(audioContext, audioCodec, NULL) < 0) {
    avcodec_free_context(&audioContext);
    NSLog(@"[XuperPad] decodificador: no se pudo abrir el decodificador de audio %ld", (long)streamIndex);
    return;
  }
  state->audio = audioContext;
  state->audioIndex = streamIndex;
  state->audioSampleRate = audioContext->sample_rate;
  state->audioChannels = audioContext->channels;
  state->audioChannelLayout = audioContext->channel_layout;

  NSString *audioCodecName = audioCodec->name != NULL
                               ? [NSString stringWithUTF8String:audioCodec->name]
                               : @"desconocido";
  NSLog(@"[XuperPad] decodificador: audio %@ %d Hz canales %d formato %d base %d/%d pista %ld",
        audioCodecName,
        audioContext->sample_rate,
        audioContext->channels,
        (int)audioContext->sample_fmt,
        audioContext->pkt_timebase.num,
        audioContext->pkt_timebase.den,
        (long)streamIndex);

  int64_t inputLayout = audioContext->channel_layout;
  if (inputLayout == 0 && audioContext->channels > 0) {
    inputLayout = av_get_default_channel_layout(audioContext->channels);
  }
  if (inputLayout == 0) {
    NSLog(@"[XuperPad] decodificador: el audio no tiene disposicion de canales utilizable");
    [self closeAudioDecoder];
    return;
  }
  if (audioContext->sample_fmt == AV_SAMPLE_FMT_NONE) {
    NSLog(@"[XuperPad] decodificador: el audio no tiene formato de muestra utilizable");
    [self closeAudioDecoder];
    return;
  }
  [clockLock lock];
  float rate = currentRate;
  [clockLock unlock];
  int sourceRate = audioContext->sample_rate > 0 ? audioContext->sample_rate : 44100;
  int outputRate = (int)((double)sourceRate * (double)rate);
  if (outputRate < 8000) {
    outputRate = 8000;
  }
  SwrContext *resample = swr_alloc_set_opts(NULL,
                                             AV_CH_LAYOUT_STEREO,
                                             AV_SAMPLE_FMT_S16,
                                             outputRate,
                                             inputLayout,
                                             (enum AVSampleFormat)audioContext->sample_fmt,
                                             audioContext->sample_rate,
                                             0,
                                             NULL);
  if (resample == NULL) {
    NSLog(@"[XuperPad] decodificador: sin memoria para el remuestreador de audio");
    [self closeAudioDecoder];
    return;
  }
  int resampleResult = swr_init(resample);
  if (resampleResult < 0) {
    NSLog(@"[XuperPad] decodificador: swr_init fallo %d %@",
          resampleResult, XPFFmpegErrorText(resampleResult));
    swr_free(&resample);
    [self closeAudioDecoder];
    return;
  }
  if (state->resample != NULL) {
    swr_free(&state->resample);
  }
  state->resample = resample;

  if (audioOutput == nil) {
    XPAudioOutput *output = [[XPAudioOutput alloc] init];
    if ([output startWithSampleRate:outputRate channels:2]) {
      audioOutput = output;
      outputSampleRate = outputRate;
      NSLog(@"[XuperPad] decodificador: salida de audio lista a %d Hz", outputRate);
    } else {
      NSLog(@"[XuperPad] decodificador: la salida de audio no pudo iniciarse");
    }
  } else if (outputSampleRate != outputRate) {
    [self resetAudioOutputWithRate:outputRate];
  }

  selectedAudioIndex = streamIndex;
  NSLog(@"[XuperPad] decodificador: pista de audio activa %ld", (long)streamIndex);
}

- (void)closeAudioDecoder
{
  if (state == NULL) {
    return;
  }
  if (state->audio != NULL) {
    avcodec_free_context(&state->audio);
    state->audio = NULL;
  }
  if (state->resample != NULL) {
    swr_free(&state->resample);
    state->resample = NULL;
  }
  state->audioIndex = -1;
  state->audioSampleRate = 0;
  state->audioChannels = 0;
  state->audioChannelLayout = 0;
}

- (void)openSubtitleForStreamIndex:(int)streamIndex
{
  if (state == NULL || state->format == NULL) {
    return;
  }
  if (streamIndex < 0 || streamIndex >= (int)state->format->nb_streams) {
    return;
  }
  AVStream *stream = state->format->streams[streamIndex];
  if (stream == NULL || stream->codecpar == NULL) {
    return;
  }
  AVCodec *codec = avcodec_find_decoder(stream->codecpar->codec_id);
  if (codec == NULL) {
    NSLog(@"[XuperPad] decodificador: la pista de subtitulos %ld no tiene decodificador",
          (long)streamIndex);
    return;
  }
  AVCodecContext *context = avcodec_alloc_context3(codec);
  if (context == NULL) {
    return;
  }
  if (avcodec_parameters_to_context(context, stream->codecpar) < 0) {
    avcodec_free_context(&context);
    return;
  }
  context->pkt_timebase = stream->time_base;
  if (avcodec_open2(context, codec, NULL) < 0) {
    avcodec_free_context(&context);
    NSLog(@"[XuperPad] decodificador: no se pudo abrir el decodificador de subtitulos %ld",
          (long)streamIndex);
    return;
  }
  state->subtitle = context;
  state->subtitleIndex = streamIndex;
  selectedSubtitleIndex = streamIndex;
  NSLog(@"[XuperPad] decodificador: pista de subtitulos activa %ld", (long)streamIndex);
}

- (void)closeSubtitleDecoder
{
  if (state == NULL) {
    return;
  }
  if (state->subtitle != NULL) {
    avcodec_free_context(&state->subtitle);
    state->subtitle = NULL;
  }
  state->subtitleIndex = -1;
}

- (double)packetTime:(AVPacket *)packet streamIndex:(int)streamIndex
{
  if (packet == NULL || state == NULL || state->format == NULL) {
    return 0.0;
  }
  if (streamIndex < 0 || streamIndex >= (int)state->format->nb_streams) {
    return 0.0;
  }
  int64_t timestamp = packet->pts;
  if (timestamp == AV_NOPTS_VALUE) {
    timestamp = packet->dts;
  }
  if (timestamp == AV_NOPTS_VALUE) {
    return 0.0;
  }
  AVRational timeBase = state->format->streams[streamIndex]->time_base;
  return timestamp * av_q2d(timeBase);
}

- (double)packetDecodeTime:(AVPacket *)packet streamIndex:(int)streamIndex
{
  if (packet == NULL || state == NULL || state->format == NULL) {
    return 0.0;
  }
  if (streamIndex < 0 || streamIndex >= (int)state->format->nb_streams) {
    return 0.0;
  }
  int64_t timestamp = packet->dts;
  if (timestamp == AV_NOPTS_VALUE) {
    timestamp = packet->pts;
  }
  if (timestamp == AV_NOPTS_VALUE) {
    return 0.0;
  }
  AVRational timeBase = state->format->streams[streamIndex]->time_base;
  return timestamp * av_q2d(timeBase);
}

- (void)decodeVideoPacket:(AVPacket *)packet generation:(int64_t)generation
{
  if (state == NULL || state->video == NULL || packet == NULL) {
    return;
  }
  double packetPTS = [self packetTime:packet streamIndex:state->videoIndex];
  [self waitForVideoPace:packetPTS];

  CFAbsoluteTime decodeStart = CFAbsoluteTimeGetCurrent();
  int sendResult = avcodec_send_packet(state->video, packet);
  if (sendResult == AVERROR(EAGAIN)) {
    [self drainVideoFrames:generation];
    sendResult = avcodec_send_packet(state->video, packet);
  }
  if (sendResult < 0) {
    videoSendErrorCount++;
    if (videoSendErrorCount <= 3) {
      NSLog(@"[XuperPad] decodificador: avcodec_send_packet fallo %d %@",
            sendResult, XPFFmpegErrorText(sendResult));
    }
    videoDecodeSeconds += CFAbsoluteTimeGetCurrent() - decodeStart;
    if (state->video != NULL) {
      avcodec_flush_buffers(state->video);
    }
    [videoCondition lock];
    videoNeedsKeyframe = YES;
    [videoCondition unlock];
    return;
  }
  [self drainVideoFrames:generation];
  videoDecodeSeconds += CFAbsoluteTimeGetCurrent() - decodeStart;
}

- (void)drainVideoFrames:(int64_t)generation
{
  while (state != NULL && state->video != NULL &&
         avcodec_receive_frame(state->video, state->videoFrame) == 0) {
    AVFrame *frame = state->videoFrame;
    if (frame->width <= 0 || frame->height <= 0 || frame->format < 0) {
      av_frame_unref(frame);
      continue;
    }
    frameCount++;
    switch (frame->pict_type) {
      case AV_PICTURE_TYPE_I: pictICount++; break;
      case AV_PICTURE_TYPE_P: pictPCount++; break;
      case AV_PICTURE_TYPE_B: pictBCount++; break;
      default: pictOtherCount++; break;
    }
    if (frameCount == 1) {
      AVRational videoTimeBase = state->format->streams[state->videoIndex]->time_base;
      NSLog(@"[XuperPad] decodificador: primer fotograma %dx%d pix %d pts %lld base %d/%d",
            frame->width, frame->height, (int)frame->format,
            (long long)frame->pts, videoTimeBase.num, videoTimeBase.den);
    }
    int64_t timestamp = frame->pts;
    if (timestamp == AV_NOPTS_VALUE) {
      timestamp = frame->best_effort_timestamp;
    }
    AVRational videoTimeBase = state->format->streams[state->videoIndex]->time_base;
    double pts = (timestamp == AV_NOPTS_VALUE) ? 0 : timestamp * av_q2d(videoTimeBase);
    if (pts > latestPTS) {
      latestPTS = pts;
    }

    int frameWidth = frame->width;
    int frameHeight = frame->height;
    XPVideoFrameData *output = nil;
    if (frame->format == AV_PIX_FMT_YUV420P || frame->format == AV_PIX_FMT_YUVJ420P) {
      output = [self yuvFrameFromFrame:frame];
    } else {
      output = [self rgbFrameFromFrame:frame];
    }
    if (output != nil) {
      output.pts = pts;
      if (generation == videoGeneration) {
        [self pushFrame:output];
      }
    }
    if (!videoSizeReported) {
      videoSizeReported = YES;
      [self reportVideoSize:frameWidth height:frameHeight];
    }
    av_frame_unref(frame);
  }
}

- (XPVideoFrameData *)yuvFrameFromFrame:(AVFrame *)frame
{
  int width = frame->width;
  int height = frame->height;
  int chromaWidth = (width + 1) / 2;
  int chromaHeight = (height + 1) / 2;
  if (frame->data[0] == NULL || frame->data[1] == NULL || frame->data[2] == NULL) {
    return nil;
  }
  BOOL tight = frame->linesize[0] == width
            && frame->linesize[1] == chromaWidth
            && frame->linesize[2] == chromaWidth;
  if (tight) {
    AVFrame *owned = av_frame_alloc();
    if (owned == NULL) {
      return nil;
    }
    av_frame_move_ref(owned, frame);
    XPVideoFrameData *result = [[XPVideoFrameData alloc] init];
    result.directUpload = YES;
    result.nativeFrame = owned;
    result.lumaPointer = owned->data[0];
    result.chromaUPointer = owned->data[1];
    result.chromaVPointer = owned->data[2];
    result.lumaStride = owned->linesize[0];
    result.chromaStride = owned->linesize[1];
    result.width = width;
    result.height = height;
    result.chromaWidth = chromaWidth;
    result.chromaHeight = chromaHeight;
    if (!directUploadActive) {
      directUploadActive = YES;
      NSLog(@"[XuperPad] decodificador: planos enviados sin copia, ancho de linea %d", owned->linesize[0]);
    }
    return result;
  }

  CFAbsoluteTime copyStart = CFAbsoluteTimeGetCurrent();
  NSData *luma = XPCopyPlane(frame->data[0], frame->linesize[0], width, height);
  NSData *chromaU = XPCopyPlane(frame->data[1], frame->linesize[1], chromaWidth, chromaHeight);
  NSData *chromaV = XPCopyPlane(frame->data[2], frame->linesize[2], chromaWidth, chromaHeight);
  copySeconds += CFAbsoluteTimeGetCurrent() - copyStart;
  if (luma == nil || chromaU == nil || chromaV == nil) {
    return nil;
  }
  XPVideoFrameData *result = [[XPVideoFrameData alloc] init];
  result.luma = luma;
  result.chromaU = chromaU;
  result.chromaV = chromaV;
  result.width = width;
  result.height = height;
  result.chromaWidth = chromaWidth;
  result.chromaHeight = chromaHeight;
  return result;
}

- (XPVideoFrameData *)rgbFrameFromFrame:(AVFrame *)frame
{
  int sourceWidth = frame->width;
  int sourceHeight = frame->height;
  int targetWidth = sourceWidth;
  int targetHeight = sourceHeight;
  CGSize requested = self.presentationSize;
  if (requested.width > 1.0 && requested.height > 1.0) {
    double factor = requested.width / (double)sourceWidth;
    double heightFactor = requested.height / (double)sourceHeight;
    if (heightFactor < factor) {
      factor = heightFactor;
    }
    if (factor < 1.0) {
      targetWidth = (int)(sourceWidth * factor);
      targetHeight = (int)(sourceHeight * factor);
    }
  }
  if (targetWidth < 16) {
    targetWidth = 16;
  }
  if (targetHeight < 16) {
    targetHeight = 16;
  }
  if (state->scale == NULL || state->width != targetWidth || state->height != targetHeight) {
    if (state->scale != NULL) {
      sws_freeContext(state->scale);
      state->scale = NULL;
    }
    state->scale = sws_getContext(sourceWidth,
                                  sourceHeight,
                                  (enum AVPixelFormat)frame->format,
                                  targetWidth,
                                  targetHeight,
                                  AV_PIX_FMT_RGB24,
                                  SWS_BILINEAR,
                                  NULL,
                                  NULL,
                                  NULL);
    if (state->scale == NULL) {
      return nil;
    }
    state->width = targetWidth;
    state->height = targetHeight;
    int size = targetWidth * targetHeight * 3;
    if (state->rgbSize < size) {
      if (state->rgb != NULL) {
        av_free(state->rgb);
        state->rgb = NULL;
        state->rgbSize = 0;
      }
      state->rgb = av_malloc((size_t)size);
      state->rgbSize = size;
    }
    NSLog(@"[XuperPad] decodificador: presentacion rgb %dx%d desde %dx%d",
          targetWidth, targetHeight, sourceWidth, sourceHeight);
  }
  if (state->rgb == NULL) {
    return nil;
  }
  uint8_t *destination[4] = { state->rgb, NULL, NULL, NULL };
  int strides[4] = { state->width * 3, 0, 0, 0 };
  const uint8_t *source[AV_NUM_DATA_POINTERS];
  for (int index = 0; index < AV_NUM_DATA_POINTERS; index++) {
    source[index] = frame->data[index];
  }
  CFAbsoluteTime scaleStart = CFAbsoluteTimeGetCurrent();
  sws_scale(state->scale, source, frame->linesize, 0, frame->height, destination, strides);
  scaleSeconds += CFAbsoluteTimeGetCurrent() - scaleStart;
  XPVideoFrameData *result = [[XPVideoFrameData alloc] init];
  result.rgb = [NSData dataWithBytes:state->rgb length:(NSUInteger)(state->width * state->height * 3)];
  result.width = state->width;
  result.height = state->height;
  return result;
}

- (void)decodeAudioPacket
{
  if (state == NULL || state->audio == NULL || state->resample == NULL) {
    return;
  }
  int sendResult = avcodec_send_packet(state->audio, state->packet);
  if (sendResult < 0) {
    if (audioPacketCount <= 2) {
      NSLog(@"[XuperPad] decodificador: audio avcodec_send_packet fallo %d %@",
            sendResult, XPFFmpegErrorText(sendResult));
    }
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
          int sampleCount = converted * 2;
          const int16_t *samples = (const int16_t *)buffer;
          for (int index = 0; index < sampleCount; index++) {
            int value = samples[index];
            if (value < 0) {
              value = -value;
            }
            if (value > pcmPeak) {
              pcmPeak = value;
            }
            pcmSquareSum += (long long)value * (long long)value;
          }
          pcmSampleCount += sampleCount;
          int64_t audioTimestamp = frame->pts;
          if (audioTimestamp == AV_NOPTS_VALUE) {
            audioTimestamp = frame->best_effort_timestamp;
          }
          AVRational audioTimeBase = state->format->streams[state->audioIndex]->time_base;
          double audioPTS = (audioTimestamp == AV_NOPTS_VALUE)
                          ? 0
                          : audioTimestamp * av_q2d(audioTimeBase);
          [clockLock lock];
          if (!hasAudioStart) {
            hasAudioStart = YES;
            audioStartPTS = audioPTS;
            if (hasVideoStart) {
              double videoNow = videoStartPTS
                              + (CFAbsoluteTimeGetCurrent() - videoWall) * (double)currentRate;
              audioOffset = videoNow - audioPTS;
            } else {
              audioOffset = 0;
            }
            lastAudioClockAt = CFAbsoluteTimeGetCurrent();
          }
          [clockLock unlock];
          if (audioPTS > latestPTS) {
            latestPTS = audioPTS;
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

- (void)decodeSubtitlePacket
{
  if (state == NULL || state->subtitle == NULL || state->packet == NULL) {
    return;
  }
  AVSubtitle subtitle;
  memset(&subtitle, 0, sizeof(subtitle));
  int got = 0;
  int result = avcodec_decode_subtitle2(state->subtitle, &subtitle, &got, state->packet);
  if (result < 0 || got == 0) {
    if (subtitlePacketCount <= 3) {
      NSLog(@"[XuperPad] decodificador: subtitulos sin datos (%d)", result);
    }
    return;
  }
  double start = [self packetTime:state->packet streamIndex:state->subtitleIndex];
  double display = (double)subtitle.start_display_time / 1000.0;
  double finish = (double)subtitle.end_display_time / 1000.0;
  double cueStart = start + display;
  double cueEnd = cueStart + (finish - display);
  if (finish <= display) {
    cueEnd = cueStart + 3.0;
  }
  NSMutableArray *cues = [NSMutableArray array];
  for (unsigned int index = 0; index < subtitle.num_rects; index++) {
    AVSubtitleRect *rect = subtitle.rects[index];
    if (rect == NULL) {
      continue;
    }
    XPSubtitleCue *cue = [[XPSubtitleCue alloc] init];
    cue.start = cueStart;
    cue.end = cueEnd;
    cue.x = rect->x;
    cue.y = rect->y;
    cue.width = rect->w;
    cue.height = rect->h;
    cue.videoWidth = state->video != NULL ? state->video->width : 0;
    cue.videoHeight = state->video != NULL ? state->video->height : 0;
    if (rect->type == SUBTITLE_TEXT && rect->text != NULL) {
      cue.text = [NSString stringWithUTF8String:rect->text];
    } else if (rect->type == SUBTITLE_ASS && rect->ass != NULL) {
      cue.text = XPASSLineText(rect->ass);
    } else if (rect->type == SUBTITLE_BITMAP && rect->data[1] != NULL && rect->data[0] != NULL) {
      cue.rgba = [self rgbaFromSubtitleRect:rect];
    }
    if (cue.text.length > 0 || cue.rgba != nil) {
      [cues addObject:cue];
    }
  }
  avsubtitle_free(&subtitle);
  if (cues.count == 0) {
    return;
  }
  [subtitleLock lock];
  [subtitleCues addObjectsFromArray:cues];
  while (subtitleCues.count > 64) {
    [subtitleCues removeObjectAtIndex:0];
  }
  [subtitleLock unlock];
  NSLog(@"[XuperPad] decodificador: subtitulo con %lu textos entre %.2f y %.2f",
        (unsigned long)cues.count, cueStart, cueEnd);
}

- (NSData *)rgbaFromSubtitleRect:(AVSubtitleRect *)rect
{
  if (rect->w <= 0 || rect->h <= 0 || rect->data[1] == NULL || rect->data[0] == NULL) {
    return nil;
  }
  int colors = rect->nb_colors > 0 ? rect->nb_colors : 16;
  const uint8_t *palette = rect->data[0];
  const uint8_t *indices = rect->data[1];
  int stride = rect->linesize[1];
  if (stride <= 0) {
    stride = rect->w;
  }
  NSMutableData *result = [NSMutableData dataWithLength:
                           (NSUInteger)((size_t)rect->w * (size_t)rect->h * 4)];
  if (result == nil) {
    return nil;
  }
  uint8_t *target = (uint8_t *)result.mutableBytes;
  for (int row = 0; row < rect->h; row++) {
    const uint8_t *line = indices + (size_t)row * (size_t)stride;
    for (int column = 0; column < rect->w; column++) {
      int index = line[column];
      uint8_t *pixel = target + ((size_t)row * (size_t)rect->w + (size_t)column) * 4;
      if (index > 0 && index < colors) {
        const uint8_t *entry = palette + (size_t)index * 4;
        pixel[0] = entry[0];
        pixel[1] = entry[1];
        pixel[2] = entry[2];
        pixel[3] = entry[3];
      } else {
        pixel[0] = 0;
        pixel[1] = 0;
        pixel[2] = 0;
        pixel[3] = 0;
      }
    }
  }
  return result;
}

- (void)pushFrame:(XPVideoFrameData *)frame
{
  [clockLock lock];
  BOOL firstFrame = !hasVideoStart;
  if (firstFrame) {
    hasVideoStart = YES;
    videoStartPTS = frame.pts;
    videoWall = CFAbsoluteTimeGetCurrent();
    double master = 0.0;
    if (hasAudioStart) {
      master = audioStartPTS + audioOffset + lastAudioClock * (double)currentRate;
    } else {
      master = videoStartPTS;
    }
    videoMasterOffset = master - frame.pts;
  }
  [clockLock unlock];
  [frameCondition lock];
  [frames addObject:frame];
  while (frames.count > XPVideoQueueLimit) {
    XPVideoFrameData *dropped = frames.firstObject;
    [frames removeObjectAtIndex:0];
    dropped = nil;
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

- (void)reportTracks
{
  NSArray *audios = [audioTracks copy];
  NSArray *subtitles = [subtitleTracks copy];
  NSInteger audioIndex = selectedAudioIndex;
  NSInteger subtitleIndex = selectedSubtitleIndex;
  dispatch_async(dispatch_get_main_queue(), ^{
    id<XPDecoderDelegate> delegate = self.delegate;
    if (delegate == nil) {
      return;
    }
    if ([delegate respondsToSelector:@selector(decoder:didUpdateAudioTracks:selectedIndex:)]) {
      [delegate decoder:self didUpdateAudioTracks:audios selectedIndex:audioIndex];
    }
    if ([delegate respondsToSelector:@selector(decoder:didUpdateSubtitleTracks:selectedIndex:)]) {
      [delegate decoder:self didUpdateSubtitleTracks:subtitles selectedIndex:subtitleIndex];
    }
  });
}

- (void)rebuildInformationText
{
  if (state == NULL || state->format == NULL) {
    informationText = @"";
    return;
  }
  NSMutableString *text = [NSMutableString string];
  if (state->video != NULL) {
    const AVCodecDescriptor *descriptor = avcodec_descriptor_get(state->video->codec_id);
    NSString *name = descriptor != NULL && descriptor->name != NULL
                       ? [NSString stringWithUTF8String:descriptor->name]
                       : @"video";
    [text appendFormat:@"%@ %dx%d", name.uppercaseString, state->video->width, state->video->height];
    if (state->video->bit_rate > 0) {
      [text appendFormat:@" · %.1f Mbps", (double)state->video->bit_rate / 1000000.0];
    }
  }
  if (state->audio != NULL) {
    const AVCodecDescriptor *descriptor = avcodec_descriptor_get(state->audio->codec_id);
    NSString *name = descriptor != NULL && descriptor->name != NULL
                       ? [NSString stringWithUTF8String:descriptor->name]
                       : @"audio";
    [text appendFormat:@" · %@ %d Hz %d canales",
      name.uppercaseString, state->audio->sample_rate, state->audio->channels];
  }
  [text appendFormat:@" · %lu pistas de audio", (unsigned long)audioTracks.count];
  if (subtitleTracks.count > 0) {
    [text appendFormat:@" · %lu pistas de subtitulos", (unsigned long)subtitleTracks.count];
  }
  informationText = [text copy];
}

- (void)setFailureDetail:(NSString *)detail
{
  if (detail.length > 0) {
    failureDetail = [detail copy];
  }
}

- (void)reportFailure:(NSString *)message
{
  NSLog(@"[XuperPad] decodificador: fallo %@ (%@)",
        message, failureDetail ?: @"sin detalle");
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
  [frameCondition lock];
  [frames removeAllObjects];
  if (pendingFrame != nil) {
    XPVideoFrameData *dropped = pendingFrame;
    pendingFrame = nil;
    dropped = nil;
  }
  [frameCondition unlock];

  [videoCondition lock];
  for (XPQueuedPacket *item in videoPackets) {
    AVPacket *queuedPacket = item.packet;
    if (queuedPacket != NULL) {
      av_packet_free(&queuedPacket);
    }
  }
  [videoPackets removeAllObjects];
  [videoCondition unlock];

  if (state == NULL) {
    return;
  }
  if (state->packet != NULL) {
    av_packet_free(&state->packet);
  }
  if (state->frame != NULL) {
    av_frame_free(&state->frame);
  }
  if (state->videoFrame != NULL) {
    av_frame_free(&state->videoFrame);
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
  if (state->subtitle != NULL) {
    avcodec_free_context(&state->subtitle);
    state->subtitle = NULL;
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
  av_log_set_callback(NULL);
}

- (void)dealloc
{
  [self stop];
}

@end
