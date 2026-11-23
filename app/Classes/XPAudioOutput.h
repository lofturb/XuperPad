#import <Foundation/Foundation.h>

@interface XPAudioOutput : NSObject

- (BOOL)startWithSampleRate:(int)sampleRate channels:(int)channels;
- (BOOL)resetWithSampleRate:(int)sampleRate channels:(int)channels;
- (void)setPaused:(BOOL)paused;
- (void)enqueuePCM:(NSData *)pcm;
- (void)setPrerollTargetSeconds:(double)seconds;
- (BOOL)isPlaybackStarted;
- (double)queuedSeconds;
- (double)playedSeconds;
- (NSUInteger)callbackCount;
- (NSUInteger)freeBufferCount;
- (float)meterPeak;
- (float)meterAverage;
- (void)stop;

@end
