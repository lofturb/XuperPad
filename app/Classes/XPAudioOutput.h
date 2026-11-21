#import <Foundation/Foundation.h>

@interface XPAudioOutput : NSObject

- (BOOL)startWithSampleRate:(int)sampleRate channels:(int)channels;
- (void)enqueuePCM:(NSData *)pcm;
- (double)queuedSeconds;
- (double)playedSeconds;
- (void)stop;

@end
