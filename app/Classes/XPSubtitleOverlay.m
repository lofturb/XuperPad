#import "XPSubtitleOverlay.h"

#import "XPDecoder.h"
#import "XPTheme.h"
#import "XPDrawnLabel.h"

@interface XPSubtitleOverlay () {
  XPDrawnLabel *textLabel;
  XPSubtitleCue *cue;
  UIImage *bitmapImage;
}
@end

@implementation XPSubtitleOverlay

- (instancetype)initWithFrame:(CGRect)frame
{
  self = [super initWithFrame:frame];
  if (self) {
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.userInteractionEnabled = NO;

    textLabel = [[XPDrawnLabel alloc] initWithFrame:CGRectZero];
    textLabel.font = XPFontMedium(15.0f);
    textLabel.textColor = [UIColor whiteColor];
    textLabel.textAlignment = NSTextAlignmentCenter;
    textLabel.numberOfLines = 0;
    textLabel.textInsets = UIEdgeInsetsMake(5.0f, 10.0f, 5.0f, 10.0f);
    textLabel.layer.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.62f].CGColor;
    textLabel.layer.cornerRadius = 7.0f;
    textLabel.layer.masksToBounds = YES;
    textLabel.hidden = YES;
    [self addSubview:textLabel];
  }
  return self;
}

- (void)showCue:(XPSubtitleCue *)newCue
{
  cue = newCue;
  if (cue == nil) {
    [self clearCue];
    return;
  }
  if (cue.text.length > 0) {
    textLabel.text = cue.text;
    textLabel.hidden = NO;
  } else {
    textLabel.text = nil;
    textLabel.hidden = YES;
  }
  bitmapImage = [self imageFromCue:cue];
  [self setNeedsLayout];
  [self setNeedsDisplay];
}

- (void)clearCue
{
  cue = nil;
  bitmapImage = nil;
  textLabel.text = nil;
  textLabel.hidden = YES;
  [self setNeedsDisplay];
}

- (UIImage *)imageFromCue:(XPSubtitleCue *)source
{
  NSData *data = source.rgba;
  if (data == nil || source.width <= 0 || source.height <= 0) {
    return nil;
  }
  size_t expected = (size_t)source.width * (size_t)source.height * 4;
  if (data.length < expected) {
    return nil;
  }
  CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
  if (provider == NULL) {
    return nil;
  }
  CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
  CGImageRef image = CGImageCreate((size_t)source.width,
                                   (size_t)source.height,
                                   8,
                                   32,
                                   (size_t)source.width * 4,
                                   space,
                                   (CGBitmapInfo)kCGImageAlphaPremultipliedLast,
                                   provider,
                                   NULL,
                                   false,
                                   kCGRenderingIntentDefault);
  CGColorSpaceRelease(space);
  CGDataProviderRelease(provider);
  if (image == NULL) {
    return nil;
  }
  UIImage *result = [UIImage imageWithCGImage:image];
  CGImageRelease(image);
  return result;
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  CGFloat width = CGRectGetWidth(self.bounds);
  CGFloat height = CGRectGetHeight(self.bounds);
  CGFloat maxWidth = MAX(80.0f, width * 0.78f);
  CGFloat bottom = height - 104.0f;
  if (bottom < 40.0f) {
    bottom = 40.0f;
  }
  CGSize fitted = CGSizeZero;
  if (textLabel.text.length > 0) {
    NSDictionary *attributes = @{ NSFontAttributeName : textLabel.font };
    CGRect box = [textLabel.text boundingRectWithSize:CGSizeMake(maxWidth - 20.0f, 60.0f)
                                              options:NSStringDrawingUsesLineFragmentOrigin
                                           attributes:attributes
                                              context:nil];
    fitted = box.size;
  }
  CGFloat boxWidth = MIN(maxWidth, fitted.width + 20.0f);
  CGFloat boxHeight = MAX(0.0f, fitted.height) + 10.0f;
  textLabel.frame = CGRectMake((width - boxWidth) / 2.0f,
                               bottom - boxHeight,
                               boxWidth,
                               boxHeight);
}

- (void)drawRect:(CGRect)rect
{
  if (bitmapImage == nil || cue == nil) {
    return;
  }
  CGFloat width = CGRectGetWidth(self.bounds);
  CGFloat height = CGRectGetHeight(self.bounds);
  CGFloat videoWidth = cue.videoWidth > 0 ? (CGFloat)cue.videoWidth : width;
  CGFloat videoHeight = cue.videoHeight > 0 ? (CGFloat)cue.videoHeight : height;
  CGFloat scale = MIN(width / videoWidth, height / videoHeight);
  CGFloat shownWidth = videoWidth * scale;
  CGFloat shownHeight = videoHeight * scale;
  CGRect videoRect = CGRectMake((width - shownWidth) / 2.0f,
                                (height - shownHeight) / 2.0f,
                                shownWidth,
                                shownHeight);
  CGFloat horizontal = videoRect.size.width / 720.0f;
  CGFloat vertical = videoRect.size.height / 576.0f;
  CGRect target = CGRectMake(CGRectGetMinX(videoRect) + cue.x * horizontal,
                              CGRectGetMinY(videoRect) + cue.y * vertical,
                              cue.width * horizontal,
                              cue.height * vertical);
  if (CGRectIsEmpty(target)) {
    return;
  }
  [bitmapImage drawInRect:target];
}

@end
