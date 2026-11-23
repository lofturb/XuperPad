#import "XPAudioOutput.h"

#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <stdlib.h>
#import <string.h>

static const int XPAudioBufferFrames = 2048;
static const int XPAudioBufferCount = 768;

@interface XPAudioOutput () {
  AudioQueueRef queue;
  AudioStreamBasicDescription format;
  NSMutableArray *freeBuffers;
  NSCondition *stateCondition;
  NSLock *queueLock;
  BOOL active;
  BOOL started;
  BOOL warnedAboutStall;
  double prerollTargetSeconds;
  int rate;
  int channelCount;
  long long samplesAccepted;
  long long samplesPlayed;
  NSUInteger callbacks;
  float meterPeak;
  float meterAverage;
}

- (AudioQueueBufferRef)takeFreeBuffer;
- (void)returnBuffer:(AudioQueueBufferRef)buffer queue:(AudioQueueRef)audioQueue;
- (void)startQueueIfNeeded;
- (BOOL)createQueueWithSampleRate:(int)sampleRate channels:(int)channels;
- (void)disposeQueue;

@end

static void XPAudioQueueCallback(void *userData, AudioQueueRef audioQueue, AudioQueueBufferRef buffer)
{
  XPAudioOutput *output = (__bridge XPAudioOutput *)userData;
  [output returnBuffer:buffer queue:audioQueue];
}

@implementation XPAudioOutput

- (instancetype)init
{
  self = [super init];
  if (self != nil) {
    freeBuffers = [NSMutableArray array];
    stateCondition = [[NSCondition alloc] init];
    queueLock = [[NSLock alloc] init];
    active = NO;
    started = NO;
    warnedAboutStall = NO;
    prerollTargetSeconds = 0.0;
    rate = 44100;
    channelCount = 2;
    samplesAccepted = 0;
    samplesPlayed = 0;
    callbacks = 0;
    meterPeak = 0;
    meterAverage = 0;
    queue = NULL;
  }
  return self;
}

- (BOOL)startWithSampleRate:(int)sampleRate channels:(int)channels
{
  if (queue != NULL) {
    return NO;
  }
  if (sampleRate <= 0 || channels <= 0) {
    return NO;
  }
  rate = sampleRate;
  channelCount = channels;

  NSError *sessionError = nil;
  AVAudioSession *session = [AVAudioSession sharedInstance];
  [session setCategory:AVAudioSessionCategoryPlayback error:&sessionError];
  if (sessionError != nil) {
    NSLog(@"[XuperPad] audio: no se pudo fijar la categoria (%@)", sessionError.localizedDescription);
    sessionError = nil;
  }
  [session setActive:YES error:&sessionError];
  BOOL sessionActivated = sessionError == nil;
  if (sessionError != nil) {
    NSLog(@"[XuperPad] audio: no se pudo activar la sesion (%@)", sessionError.localizedDescription);
    sessionError = nil;
  }

  NSMutableArray *routeNames = [NSMutableArray array];
  for (AVAudioSessionPortDescription *output in session.currentRoute.outputs) {
    [routeNames addObject:[NSString stringWithFormat:@"%@ %@", output.portType, output.portName]];
  }
  NSLog(@"[XuperPad] audio: sesion activa %d tasa %.0f canales %u volumen %.2f salidas %@",
        (int)sessionActivated,
        session.sampleRate,
        (unsigned int)session.outputNumberOfChannels,
        (float)session.outputVolume,
        routeNames);

  return [self createQueueWithSampleRate:sampleRate channels:channels];
}

- (BOOL)createQueueWithSampleRate:(int)sampleRate channels:(int)channels
{
  if (sampleRate <= 0 || channels <= 0) {
    return NO;
  }
  rate = sampleRate;
  channelCount = channels;

  memset(&format, 0, sizeof(format));
  format.mSampleRate = sampleRate;
  format.mFormatID = kAudioFormatLinearPCM;
  format.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
  format.mFramesPerPacket = 1;
  format.mChannelsPerFrame = channels;
  format.mBitsPerChannel = 16;
  format.mBytesPerFrame = channels * 2;
  format.mBytesPerPacket = channels * 2;

  AudioQueueRef created = NULL;
  OSStatus status = AudioQueueNewOutput(&format,
                                        XPAudioQueueCallback,
                                        (__bridge void *)self,
                                        NULL,
                                        NULL,
                                        0,
                                        &created);
  if (status != noErr || created == NULL) {
    NSLog(@"[XuperPad] audio: AudioQueueNewOutput fallo %d", (int)status);
    return NO;
  }
  queue = created;
  UInt32 metering = 1;
  OSStatus meteringStatus = AudioQueueSetProperty(queue,
                                                  kAudioQueueProperty_EnableLevelMetering,
                                                  &metering,
                                                  sizeof(metering));
  if (meteringStatus != noErr) {
    NSLog(@"[XuperPad] audio: no se pudo activar el medidor (%d)", (int)meteringStatus);
  }

  UInt32 capacity = (UInt32)(XPAudioBufferFrames * channels * 2);
  for (int index = 0; index < XPAudioBufferCount; index++) {
    AudioQueueBufferRef buffer = NULL;
    status = AudioQueueAllocateBuffer(queue, capacity, &buffer);
    if (status != noErr || buffer == NULL) {
      break;
    }
    memset(buffer->mAudioData, 0, capacity);
    buffer->mAudioDataByteSize = capacity;
    [freeBuffers addObject:[NSValue valueWithPointer:buffer]];
  }
  if (freeBuffers.count == 0) {
    NSLog(@"[XuperPad] audio: no se pudieron asignar los buffers de salida");
    AudioQueueDispose(queue, true);
    queue = NULL;
    return NO;
  }
  active = YES;
  NSLog(@"[XuperPad] audio: cola creada con %lu buffers de %d tramas a %d Hz",
        (unsigned long)freeBuffers.count, XPAudioBufferFrames, sampleRate);
  return YES;
}

- (void)disposeQueue
{
  AudioQueueRef current = NULL;
  [queueLock lock];
  current = queue;
  queue = NULL;
  [queueLock unlock];

  [stateCondition lock];
  active = NO;
  [freeBuffers removeAllObjects];
  [stateCondition broadcast];
  [stateCondition unlock];

  if (current != NULL) {
    AudioQueueStop(current, true);
    AudioQueueDispose(current, true);
  }

  [stateCondition lock];
  started = NO;
  samplesAccepted = 0;
  samplesPlayed = 0;
  callbacks = 0;
  meterPeak = 0;
  meterAverage = 0;
  [stateCondition unlock];
}

- (BOOL)resetWithSampleRate:(int)sampleRate channels:(int)channels
{
  if (sampleRate <= 0 || channels <= 0) {
    return NO;
  }
  [self disposeQueue];
  return [self createQueueWithSampleRate:sampleRate channels:channels];
}

- (void)setPaused:(BOOL)paused
{
  if (queue == NULL) {
    return;
  }
  [stateCondition lock];
  BOOL canStart = started;
  [stateCondition unlock];
  [queueLock lock];
  if (queue != NULL) {
    if (paused) {
      AudioQueuePause(queue);
    } else if (canStart) {
      OSStatus status = AudioQueueStart(queue, NULL);
      if (status != noErr) {
        NSLog(@"[XuperPad] audio: no se pudo reanudar la cola (%d)", (int)status);
      }
    }
  }
  [queueLock unlock];
}

- (void)enqueuePCM:(NSData *)pcm
{
  if (pcm.length == 0 || queue == NULL) {
    return;
  }
  const uint8_t *source = (const uint8_t *)pcm.bytes;
  NSUInteger total = pcm.length;
  NSUInteger offset = 0;
  while (offset < total) {
    AudioQueueBufferRef buffer = [self takeFreeBuffer];
    if (buffer == NULL) {
      if (!warnedAboutStall) {
        warnedAboutStall = YES;
        NSLog(@"[XuperPad] audio: la cola de salida no avanza, se descarta audio");
      }
      return;
    }
    warnedAboutStall = NO;
    UInt32 capacity = buffer->mAudioDataByteSize;
    if (capacity == 0) {
      continue;
    }
    NSUInteger take = total - offset;
    if (take > (NSUInteger)capacity) {
      take = (NSUInteger)capacity;
    }
    memcpy(buffer->mAudioData, source + offset, take);
    buffer->mAudioDataByteSize = (UInt32)take;

    [stateCondition lock];
    samplesAccepted += (long long)(take / (2 * channelCount));
    [stateCondition unlock];

    [queueLock lock];
    if (queue == NULL) {
      [queueLock unlock];
      return;
    }
    AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
    [queueLock unlock];

    offset += take;
    [self startQueueIfNeeded];
  }
}

- (AudioQueueBufferRef)takeFreeBuffer
{
  [stateCondition lock];
  CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + 1.0;
  while (active && freeBuffers.count == 0) {
    if (CFAbsoluteTimeGetCurrent() > deadline) {
      [stateCondition unlock];
      return NULL;
    }
    [stateCondition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
  }
  AudioQueueBufferRef buffer = NULL;
  if (freeBuffers.count > 0) {
    NSValue *value = [freeBuffers lastObject];
    [freeBuffers removeLastObject];
    buffer = (AudioQueueBufferRef)[value pointerValue];
  }
  [stateCondition unlock];
  return buffer;
}

- (void)returnBuffer:(AudioQueueBufferRef)buffer queue:(AudioQueueRef)audioQueue
{
  if (buffer == NULL) {
    return;
  }
  UInt32 played = buffer->mAudioDataByteSize;
  float peak = 0;
  float average = 0;
  BOOL hasLevel = NO;
  if (audioQueue != NULL && channelCount > 0) {
    AudioQueueLevelMeterState *levels = calloc((size_t)channelCount, sizeof(AudioQueueLevelMeterState));
    if (levels != NULL) {
      UInt32 levelSize = (UInt32)(sizeof(AudioQueueLevelMeterState) * channelCount);
      if (AudioQueueGetProperty(audioQueue,
                                kAudioQueueProperty_CurrentLevelMeterDB,
                                levels,
                                &levelSize) == noErr) {
        for (int index = 0; index < channelCount; index++) {
          if (levels[index].mPeakPower > peak) {
            peak = levels[index].mPeakPower;
          }
          if (levels[index].mAveragePower > average) {
            average = levels[index].mAveragePower;
          }
        }
        hasLevel = YES;
      }
      free(levels);
    }
  }
  [stateCondition lock];
  if (active) {
    callbacks++;
    if (hasLevel) {
      meterPeak = peak;
      meterAverage = average;
    }
    samplesPlayed += (long long)(played / (UInt32)(2 * channelCount));
    buffer->mAudioDataByteSize = (UInt32)(XPAudioBufferFrames * channelCount * 2);
    [freeBuffers addObject:[NSValue valueWithPointer:buffer]];
    [stateCondition broadcast];
  }
  [stateCondition unlock];
}

- (void)startQueueIfNeeded
{
  [stateCondition lock];
  BOOL shouldStart = NO;
  if (!started) {
    long long queued = samplesAccepted - samplesPlayed;
    double seconds = rate > 0 ? (double)queued / (double)rate : 0.0;
    if (seconds >= prerollTargetSeconds) {
      started = YES;
      shouldStart = YES;
    }
  }
  [stateCondition unlock];
  if (shouldStart) {
    [queueLock lock];
    if (queue != NULL) {
      OSStatus status = AudioQueueStart(queue, NULL);
      if (status != noErr) {
        NSLog(@"[XuperPad] audio: AudioQueueStart fallo %d", (int)status);
      } else {
        NSLog(@"[XuperPad] audio: la cola de sonido empezo a reproducir");
      }
    }
    [queueLock unlock];
  }
}

- (void)setPrerollTargetSeconds:(double)seconds
{
  [stateCondition lock];
  prerollTargetSeconds = seconds > 0.0 ? seconds : 0.0;
  [stateCondition unlock];
}

- (BOOL)isPlaybackStarted
{
  [stateCondition lock];
  BOOL value = started;
  [stateCondition unlock];
  return value;
}

- (double)queuedSeconds
{
  [stateCondition lock];
  long long queued = samplesAccepted - samplesPlayed;
  [stateCondition unlock];
  if (queued < 0) {
    queued = 0;
  }
  return (double)queued / (double)rate;
}

- (double)playedSeconds
{
  [stateCondition lock];
  long long played = samplesPlayed;
  [stateCondition unlock];
  if (played < 0) {
    played = 0;
  }
  return (double)played / (double)rate;
}

- (NSUInteger)callbackCount
{
  [stateCondition lock];
  NSUInteger count = callbacks;
  [stateCondition unlock];
  return count;
}

- (NSUInteger)freeBufferCount
{
  [stateCondition lock];
  NSUInteger count = freeBuffers.count;
  [stateCondition unlock];
  return count;
}

- (float)meterPeak
{
  [stateCondition lock];
  float value = meterPeak;
  [stateCondition unlock];
  return value;
}

- (float)meterAverage
{
  [stateCondition lock];
  float value = meterAverage;
  [stateCondition unlock];
  return value;
}

- (void)stop
{
  if (queue == NULL) {
    return;
  }

  [self disposeQueue];

  NSError *sessionError = nil;
  [[AVAudioSession sharedInstance] setActive:NO
                                 withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                                       error:&sessionError];
}

- (void)dealloc
{
  [self stop];
}

@end
