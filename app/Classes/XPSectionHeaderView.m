//
//  XPSectionHeaderView.m
//

#import "XPSectionHeaderView.h"
#import "XPTheme.h"

@interface XPSectionHeaderView ()
@property (nonatomic, copy) NSString *sectionTitle;
@property (nonatomic, assign) NSUInteger itemCount;
@end

@implementation XPSectionHeaderView

- (instancetype)initWithFrame:(CGRect)frame
{
  self = [super initWithFrame:frame];
  if (self) {
    self.backgroundColor = [UIColor clearColor];
    self.contentMode = UIViewContentModeRedraw;
    self.itemCount = 0;
  }
  return self;
}

- (void)applyTitle:(NSString *)title count:(NSUInteger)count
{
  self.sectionTitle = [title copy];
  self.itemCount = count;
  [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect
{
  CGContextRef context = UIGraphicsGetCurrentContext();
  if (context == NULL) {
    return;
  }
  CGFloat barHeight = 13.0f;
  CGRect bar = CGRectMake(12.0f,
                          (CGRectGetHeight(self.bounds) - barHeight) / 2.0f,
                          3.0f,
                          barHeight);
  [XPColorAccent() setFill];
  [XPRoundedPath(bar, 1.5f) fill];

  NSString *title = self.sectionTitle ?: @"";
  NSDictionary *attributes = @{ NSFontAttributeName : XPFontMedium(12.5f),
                                NSForegroundColorAttributeName : XPColorTextPrimary() };
  CGSize fitted = [title sizeWithAttributes:attributes];
  CGRect textRect = CGRectMake(21.0f,
                                (CGRectGetHeight(self.bounds) - fitted.height) / 2.0f,
                                fitted.width,
                                fitted.height);
  [title drawInRect:textRect withAttributes:attributes];

  if (self.itemCount == 0) {
    return;
  }
  NSString *counter = [NSString stringWithFormat:@"%lu", (unsigned long)self.itemCount];
  NSDictionary *counterAttributes = @{ NSFontAttributeName : XPFontCaption(10.5f),
                                       NSForegroundColorAttributeName : XPColorTextMuted() };
  CGSize counterSize = [counter sizeWithAttributes:counterAttributes];
  CGRect counterRect = CGRectMake(CGRectGetMaxX(textRect) + 6.0f,
                                   (CGRectGetHeight(self.bounds) - counterSize.height) / 2.0f,
                                   counterSize.width,
                                   counterSize.height);
  [counter drawInRect:counterRect withAttributes:counterAttributes];
}

@end
