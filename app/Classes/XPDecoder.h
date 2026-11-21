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

@protocol XPDecoderDelegate <NSObject>
- (void)decoder:(XPDecoder *)decoder didProduceVideoFrame:(XPVideoFrameData *)frame;
- (void)decoder:(XPDecoder *)decoder didOpenVideoWithWidth:(int)width height:(int)height;
- (void)decoder:(XPDecoder *)decoder didFailWithMessage:(NSString *)message;
- (void)decoder:(XPDecoder *)decoder didFinishWithMessage:(NSString *)message;
@end

@interface XPDecoder : NSObject

@property (nonatomic, weak) id<XPDecoderDelegate> delegate;
@property (nonatomic, assign) CGSize presentationSize;
@property (nonatomic, assign, getter=isPaused) BOOL paused;
@property (nonatomic, readonly) double duration;
@property (nonatomic, readonly) double currentTime;

- (BOOL)startWithAddress:(NSString *)address headers:(NSDictionary *)headers;
- (void)stop;
- (BOOL)isRunning;
- (BOOL)seekToTime:(double)seconds;

@end
