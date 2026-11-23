//
//  XPStatusView.m
//

#import "XPStatusView.h"
#import "XPTheme.h"
#import "XPButton.h"
#import "XPDrawnLabel.h"

#import <QuartzCore/QuartzCore.h>

static const double XPPiValue = 3.14159265358979323846;

@interface XPRingView : UIView
- (void)startAnimating;
- (void)stopAnimating;
@end

@implementation XPRingView

- (instancetype)initWithFrame:(CGRect)frame
{
  self = [super initWithFrame:frame];
  if (self) {
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;
  }
  return self;
}

- (void)drawRect:(CGRect)rect
{
  CGContextRef context = UIGraphicsGetCurrentContext();
  if (context == NULL) {
    return;
  }
  CGFloat side = MIN(CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds));
  CGRect area = CGRectMake((CGRectGetWidth(self.bounds) - side) / 2.0f,
                            (CGRectGetHeight(self.bounds) - side) / 2.0f,
                            side,
                            side);
  CGContextSetLineWidth(context, 2.5f);
  CGContextSetLineCap(context, kCGLineCapRound);
  CGContextSetStrokeColorWithColor(context, [XPColorSurfaceAlt() CGColor]);
  CGContextAddArc(context,
                  CGRectGetMidX(area),
                  CGRectGetMidY(area),
                  side / 2.0f - 2.0f,
                  0.0f,
                  (float)(2.0 * XPPiValue),
                  0);
  CGContextStrokePath(context);

  CGContextSetStrokeColorWithColor(context, [XPColorAccent() CGColor]);
  CGContextAddArc(context,
                  CGRectGetMidX(area),
                  CGRectGetMidY(area),
                  side / 2.0f - 2.0f,
                  (float)(-XPPiValue / 2.0),
                  (float)(XPPiValue * 0.7),
                  0);
  CGContextStrokePath(context);
}

- (void)startAnimating
{
  self.hidden = NO;
  [self.layer removeAnimationForKey:@"XPXPRingSpin"];
  CABasicAnimation *spin = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
  spin.byValue = @(2.0 * XPPiValue);
  spin.duration = 1.0;
  spin.repeatCount = HUGE_VALF;
  spin.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
  [self.layer addAnimation:spin forKey:@"XPXPRingSpin"];
}

- (void)stopAnimating
{
  [self.layer removeAnimationForKey:@"XPXPRingSpin"];
  self.transform = CGAffineTransformIdentity;
}

@end

@interface XPStatusView ()
@property (nonatomic, strong) XPRingView *ringView;
@property (nonatomic, strong) XPDrawnLabel *messageLabel;
@property (nonatomic, strong) XPButton *retryButton;
@end

@implementation XPStatusView

- (instancetype)initWithFrame:(CGRect)frame
{
  self = [super initWithFrame:frame];
  if (self) {
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;

    self.ringView = [[XPRingView alloc] initWithFrame:CGRectZero];
    [self addSubview:self.ringView];

    self.messageLabel = [[XPDrawnLabel alloc] initWithFrame:CGRectZero];
    self.messageLabel.font = XPFontBody(13.0f);
    self.messageLabel.textColor = XPColorTextMuted();
    self.messageLabel.textAlignment = NSTextAlignmentCenter;
    self.messageLabel.numberOfLines = 0;
    [self addSubview:self.messageLabel];

    self.retryButton = [[XPButton alloc] initWithTitle:@"Reintentar"
                                                 style:XPButtonStyleGhost];
    [self.retryButton addTarget:self
                          action:@selector(retryTapped:)
                forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.retryButton];

    self.hidden = YES;
  }
  return self;
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  CGFloat width = CGRectGetWidth(self.bounds);
  CGFloat height = CGRectGetHeight(self.bounds);
  CGFloat centerY = height / 2.0f - 18.0f;

  self.ringView.frame = CGRectMake(width / 2.0f - 16.0f, centerY - 16.0f, 32.0f, 32.0f);
  self.messageLabel.frame = CGRectMake(24.0f, centerY + 26.0f, width - 48.0f, 54.0f);
  self.retryButton.frame = CGRectMake(width / 2.0f - 60.0f, centerY + 86.0f, 120.0f, 34.0f);
}

- (void)showLoading
{
  self.hidden = NO;
  self.messageLabel.hidden = YES;
  self.retryButton.hidden = YES;
  self.ringView.hidden = NO;
  [self.ringView startAnimating];
  [self setNeedsLayout];
}

- (void)showMessage:(NSString *)message retry:(BOOL)retry
{
  self.hidden = NO;
  [self.ringView stopAnimating];
  self.ringView.hidden = YES;
  self.messageLabel.hidden = NO;
  self.messageLabel.text = message ?: @"";
  self.retryButton.hidden = !retry;
  [self setNeedsLayout];
}

- (void)hideStatus
{
  [self.ringView stopAnimating];
  self.hidden = YES;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
  UIView *hit = [super hitTest:point withEvent:event];
  if (hit == self) {
    return nil;
  }
  return hit;
}

- (void)retryTapped:(id)sender
{
  if (self.retryHandler != nil) {
    self.retryHandler();
  }
}

@end
