//
//  XPDrawnScrollView.m
//

#import "XPDrawnScrollView.h"

@interface XPDrawnScrollView ()
@property (nonatomic, assign) CGPoint panStart;
@property (nonatomic, assign) CGSize appliedSize;
@end

@implementation XPDrawnScrollView

- (instancetype)initWithFrame:(CGRect)frame
{
  self = [super initWithFrame:frame];
  if (self) {
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.clipsToBounds = YES;
    _scrollsHorizontally = NO;
    _scrollsVertically = YES;
    _contentSize = CGSizeZero;
    _contentOffset = CGPointZero;
    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self addGestureRecognizer:pan];
  }
  return self;
}

- (CGPoint)clampedOffset:(CGPoint)offset
{
  CGSize size = self.frame.size;
  CGFloat maxX = MAX(0.0f, self.contentSize.width - size.width);
  CGFloat maxY = MAX(0.0f, self.contentSize.height - size.height);
  if (!self.scrollsHorizontally) {
    maxX = 0.0f;
  }
  if (!self.scrollsVertically) {
    maxY = 0.0f;
  }
  CGFloat x = MAX(0.0f, MIN(maxX, offset.x));
  CGFloat y = MAX(0.0f, MIN(maxY, offset.y));
  return CGPointMake(x, y);
}

- (void)applyOffset
{
  CGSize size = self.frame.size;
  if (size.width <= 0.0f || size.height <= 0.0f) {
    return;
  }
  CGRect target = CGRectMake(self.contentOffset.x,
                             self.contentOffset.y,
                             size.width,
                             size.height);
  if (CGRectEqualToRect(self.bounds, target)) {
    return;
  }
  self.bounds = target;
}

- (void)setContentOffset:(CGPoint)contentOffset
{
  _contentOffset = [self clampedOffset:contentOffset];
  [self applyOffset];
}

- (void)setContentOffset:(CGPoint)contentOffset animated:(BOOL)animated
{
  if (!animated) {
    [self setContentOffset:contentOffset];
    return;
  }
  CGPoint target = [self clampedOffset:contentOffset];
  [UIView animateWithDuration:0.25
                        delay:0.0
                      options:UIViewAnimationOptionCurveEaseOut
                   animations:^{
    _contentOffset = target;
    [self applyOffset];
  } completion:nil];
}

- (void)setContentSize:(CGSize)contentSize
{
  _contentSize = contentSize;
  _contentOffset = [self clampedOffset:_contentOffset];
  [self applyOffset];
}

- (void)setScrollsHorizontally:(BOOL)scrollsHorizontally
{
  _scrollsHorizontally = scrollsHorizontally;
  [self setContentOffset:_contentOffset];
}

- (void)setScrollsVertically:(BOOL)scrollsVertically
{
  _scrollsVertically = scrollsVertically;
  [self setContentOffset:_contentOffset];
}

- (void)handlePan:(UIPanGestureRecognizer *)pan
{
  if (pan.state == UIGestureRecognizerStateBegan) {
    self.panStart = self.contentOffset;
    return;
  }
  if (pan.state == UIGestureRecognizerStateChanged) {
    CGPoint translation = [pan translationInView:self];
    CGPoint target = CGPointMake(self.panStart.x - translation.x,
                                 self.panStart.y - translation.y);
    self.contentOffset = target;
    return;
  }
  if (pan.state == UIGestureRecognizerStateEnded ||
      pan.state == UIGestureRecognizerStateCancelled) {
    CGPoint velocity = [pan velocityInView:self];
    CGSize size = self.frame.size;
    CGPoint target = self.contentOffset;
    if (self.scrollsHorizontally) {
      target.x -= velocity.x * 0.18f;
    }
    if (self.scrollsVertically) {
      target.y -= velocity.y * 0.18f;
    }
    target = [self clampedOffset:target];
    if (size.width <= 0.0f) {
      return;
    }
    [self setContentOffset:target animated:YES];
  }
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  CGSize size = self.bounds.size;
  if (!CGSizeEqualToSize(size, self.appliedSize)) {
    self.appliedSize = size;
    self.contentOffset = [self clampedOffset:self.contentOffset];
    [self applyOffset];
  }
}

@end
