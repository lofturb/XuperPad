#import "XPAudioOutput.h"

#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <string.h>

static const int XPAudioBufferFrames = 4096;
static const int XPAudioBufferCount = 4;

@interface XPAudioOutput () {
  AudioQueueRef queue;
  AudioStreamBasicDescription format;
  NSMutableArray *freeBuffers;
  NSCondition *stateCondition;
  NSLock *queueLock;
  BOOL active;
  BOOL started;
  BOOL warnedAboutStall;
  int rate;
  int channelCount;
  long long samplesAccepted;
  long long samplesPlayed;
}

- (AudioQueueBufferRef)takeFreeBuffer;
- (void)returnBuffer:(AudioQueueBufferRef)buffer;
- (void)startQueueIfNeeded;

@end

static void XPAudioQueueCallback(void *userData, AudioQueueRef audioQueue, AudioQueueBufferRef buffer)
{
  XPAudioOutput *output = (__bridge XPAudioOutput *)userData;
  [output returnBuffer:buffer];
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
    rate = 44100;
    channelCount = 2;
    samplesAccepted = 0;
    samplesPlayed = 0;
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
  if (sessionError != nil) {
    NSLog(@"[XuperPad] audio: no se pudo activar la sesion (%@)", sessionError.localizedDescription);
    sessionError = nil;
  }

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
  NSLog(@"[XuperPad] audio: cola creada con %lu buffers de %d tramas",
        (unsigned long)freeBuffers.count, XPAudioBufferFrames);
  return YES;
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

- (void)returnBuffer:(AudioQueueBufferRef)buffer
{
  if (buffer == NULL) {
    return;
  }
  UInt32 played = buffer->mAudioDataByteSize;
  [stateCondition lock];
  if (active) {
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
  BOOL shouldStart = !started;
  started = YES;
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

- (void)stop
{
  if (queue == NULL) {
    return;
  }

  [queueLock lock];
  AudioQueueStop(queue, true);

  [stateCondition lock];
  active = NO;
  [freeBuffers removeAllObjects];
  [stateCondition broadcast];
  [stateCondition unlock];

  AudioQueueDispose(queue, true);
  queue = NULL;
  [queueLock unlock];

  [stateCondition lock];
  started = NO;
  samplesAccepted = 0;
  samplesPlayed = 0;
  [stateCondition unlock];

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
