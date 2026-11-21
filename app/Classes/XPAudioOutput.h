#import <Foundation/Foundation.h>

@interface XPAudioOutput : NSObject

- (BOOL)startWithSampleRate:(int)sampleRate channels:(int)channels;
- (void)enqueuePCM:(NSData *)pcm;
- (double)queuedSeconds;
- (double)playedSeconds;
- (NSUInteger)callbackCount;
- (NSUInteger)freeBufferCount;
- (float)meterPeak;
- (float)meterAverage;
- (void)stop;

@end
