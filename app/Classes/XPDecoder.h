#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@class XPDecoder;

@interface XPVideoFrameData : NSObject
@property (nonatomic, strong) NSData *rgb;
@property (nonatomic, strong) NSData *luma;
@property (nonatomic, strong) NSData *chromaU;
@property (nonatomic, strong) NSData *chromaV;
@property (nonatomic, assign) int width;
@property (nonatomic, assign) int height;
@property (nonatomic, assign) int chromaWidth;
@property (nonatomic, assign) int chromaHeight;
@property (nonatomic, assign) double pts;
@property (nonatomic, assign) BOOL directUpload;
@property (nonatomic, assign) const void *lumaPointer;
@property (nonatomic, assign) const void *chromaUPointer;
@property (nonatomic, assign) const void *chromaVPointer;
@property (nonatomic, assign) int lumaStride;
@property (nonatomic, assign) int chromaStride;
@property (nonatomic, assign) void *nativeFrame;
@end

@interface XPTrackInfo : NSObject
@property (nonatomic, assign) NSInteger streamIndex;
@property (nonatomic, copy) NSString *languageCode;
@property (nonatomic, copy) NSString *languageName;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *codecName;
@property (nonatomic, assign) BOOL original;
@property (nonatomic, assign) BOOL available;
@end

@interface XPSubtitleCue : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) NSData *rgba;
@property (nonatomic, assign) int width;
@property (nonatomic, assign) int height;
@property (nonatomic, assign) int x;
@property (nonatomic, assign) int y;
@property (nonatomic, assign) double start;
@property (nonatomic, assign) double end;
@property (nonatomic, assign) int videoWidth;
@property (nonatomic, assign) int videoHeight;
@end

@protocol XPDecoderDelegate <NSObject>
- (void)decoder:(XPDecoder *)decoder didProduceVideoFrame:(XPVideoFrameData *)frame;
- (void)decoder:(XPDecoder *)decoder didOpenVideoWithWidth:(int)width height:(int)height;
- (void)decoder:(XPDecoder *)decoder didFailWithMessage:(NSString *)message;
- (void)decoder:(XPDecoder *)decoder didFinishWithMessage:(NSString *)message;
@optional
- (void)decoder:(XPDecoder *)decoder didUpdateAudioTracks:(NSArray *)tracks selectedIndex:(NSInteger)selectedIndex;
- (void)decoder:(XPDecoder *)decoder didUpdateSubtitleTracks:(NSArray *)tracks selectedIndex:(NSInteger)selectedIndex;
@end

@interface XPDecoder : NSObject

@property (nonatomic, weak) id<XPDecoderDelegate> delegate;
@property (nonatomic, assign) CGSize presentationSize;
@property (nonatomic, assign, getter=isPaused) BOOL paused;
@property (nonatomic, readonly) double duration;
@property (nonatomic, readonly) double currentTime;
@property (nonatomic, readonly) NSArray *audioTracks;
@property (nonatomic, readonly) NSArray *subtitleTracks;
@property (nonatomic, readonly) NSInteger selectedAudioTrackIndex;
@property (nonatomic, readonly) NSInteger selectedSubtitleTrackIndex;
@property (nonatomic, readonly) XPSubtitleCue *activeSubtitle;
@property (nonatomic, readonly) NSString *informationText;
@property (nonatomic, assign) float playbackRate;

- (BOOL)startWithAddress:(NSString *)address headers:(NSDictionary *)headers;
- (void)stop;
- (BOOL)isRunning;
- (BOOL)seekToTime:(double)seconds;
- (BOOL)selectAudioTrack:(NSInteger)streamIndex;
- (BOOL)selectSubtitleTrack:(NSInteger)streamIndex;

@end
