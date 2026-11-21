#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@class XPDecoder;

@protocol XPDecoderDelegate <NSObject>
- (void)decoder:(XPDecoder *)decoder didProduceVideoFrame:(NSData *)rgb width:(int)width height:(int)height;
- (void)decoder:(XPDecoder *)decoder didOpenVideoWithWidth:(int)width height:(int)height;
- (void)decoder:(XPDecoder *)decoder didFailWithMessage:(NSString *)message;
- (void)decoder:(XPDecoder *)decoder didFinishWithMessage:(NSString *)message;
@end

@interface XPDecoder : NSObject

@property (nonatomic, weak) id<XPDecoderDelegate> delegate;
@property (nonatomic, assign) CGSize presentationSize;

- (BOOL)startWithAddress:(NSString *)address headers:(NSDictionary *)headers;
- (void)stop;
- (BOOL)isRunning;

@end
