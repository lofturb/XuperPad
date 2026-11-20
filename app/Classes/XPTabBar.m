//
//  XPTabBar.m
//

#import "XPTabBar.h"
#import "XPTheme.h"

@interface XPTabBar ()
@property (nonatomic, strong) NSArray *tabTitles;
@property (nonatomic, strong) NSArray *tabIcons;
@end

@implementation XPTabBar

- (instancetype)initWithTitles:(NSArray *)titles icons:(NSArray *)icons
{
  self = [super initWithFrame:CGRectZero];
  if (self) {
    _tabTitles = [titles copy];
    _tabIcons = [icons copy];
    self.backgroundColor = XPColorSurface();
    self.opaque = YES;
    self.contentMode = UIViewContentModeRedraw;
    self.selectedIndex = 0;
  }
  return self;
}

- (void)setSelectedIndex:(NSUInteger)selectedIndex
{
  _selectedIndex = selectedIndex;
  [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect
{
  CGContextRef context = UIGraphicsGetCurrentContext();
  if (context == NULL) {
    return;
  }
  [XPColorDivider() setFill];
  CGContextFillRect(context, CGRectMake(0, 0, CGRectGetWidth(self.bounds), 1.0f / [UIScreen mainScreen].scale));

  NSUInteger count = self.tabTitles.count;
  if (count == 0) {
    return;
  }
  CGFloat width = CGRectGetWidth(self.bounds) / (CGFloat)count;
  CGFloat height = CGRectGetHeight(self.bounds);

  for (NSUInteger index = 0; index < count; index++) {
    BOOL active = index == self.selectedIndex;
    UIColor *tint = active ? XPColorAccent() : XPColorTextMuted();
    CGFloat centerX = width * ((CGFloat)index + 0.5f);
    CGRect iconBox = CGRectMake(centerX - 10.0f, 8.0f, 20.0f, 20.0f);
    [self drawIcon:[self.tabIcons[index] isKindOfClass:[NSString class]]
                   ? (NSString *)self.tabIcons[index]
                   : @"grid"
               inRect:iconBox
             context:context
               color:tint];

    NSString *title = [self.tabTitles[index] isKindOfClass:[NSString class]]
      ? (NSString *)self.tabTitles[index]
      : @"";
    NSDictionary *attributes = @{ NSFontAttributeName : XPFontCaption(active ? 10.0f : 9.5f),
                                  NSForegroundColorAttributeName : tint };
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    NSMutableDictionary *finalAttributes = [attributes mutableCopy];
    [finalAttributes setObject:style forKey:NSParagraphStyleAttributeName];
    CGSize fitted = [title sizeWithAttributes:finalAttributes];
    CGRect textRect = CGRectMake(centerX - width / 2.0f,
                                  height - fitted.height - 7.0f,
                                  width,
                                  fitted.height);
    [title drawInRect:textRect withAttributes:finalAttributes];
  }
}

- (void)drawIcon:(NSString *)identifier
           inRect:(CGRect)area
          context:(CGContextRef)context
            color:(UIColor *)color
{
  [color setStroke];
  [color setFill];
  if ([identifier isEqualToString:@"live"]) {
    CGRect screen = CGRectMake(CGRectGetMinX(area),
                               CGRectGetMinY(area) + 4.0f,
                               CGRectGetWidth(area),
                               13.0f);
    UIBezierPath *frame = XPRoundedPath(screen, 3.0f);
    frame.lineWidth = 1.6f;
    [frame stroke];

    UIBezierPath *triangle = [UIBezierPath bezierPath];
    [triangle moveToPoint:CGPointMake(CGRectGetMinX(screen) + 7.0f, CGRectGetMinY(screen) + 7.0f)];
    [triangle addLineToPoint:CGPointMake(CGRectGetMinX(screen) + 7.0f, CGRectGetMaxY(screen) - 3.0f)];
    [triangle addLineToPoint:CGPointMake(CGRectGetMinX(screen) + 13.0f, CGRectGetMidY(screen))];
    [triangle closePath];
    [triangle fill];

    UIBezierPath *stand = [UIBezierPath bezierPath];
    [stand moveToPoint:CGPointMake(CGRectGetMinX(area) + 4.0f, CGRectGetMaxY(area) - 1.0f)];
    [stand addLineToPoint:CGPointMake(CGRectGetMaxX(area) - 4.0f, CGRectGetMaxY(area) - 1.0f)];
    stand.lineWidth = 1.6f;
    stand.lineCapStyle = kCGLineCapRound;
    [stand stroke];
    return;
  }

  CGFloat side = 8.0f;
  CGFloat gap = 3.0f;
  for (NSInteger row = 0; row < 2; row++) {
    for (NSInteger column = 0; column < 2; column++) {
      CGRect square = CGRectMake(CGRectGetMinX(area) + column * (side + gap),
                                  CGRectGetMinY(area) + row * (side + gap),
                                  side,
                                  side);
      UIBezierPath *path = XPRoundedPath(square, 2.0f);
      [path fill];
    }
  }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
  UITouch *touch = [touches anyObject];
  CGPoint point = [touch locationInView:self];
  NSUInteger count = self.tabTitles.count;
  if (count == 0) {
    return;
  }
  CGFloat width = CGRectGetWidth(self.bounds) / (CGFloat)count;
  NSInteger index = (NSInteger)floor(point.x / width);
  if (index < 0 || (NSUInteger)index >= count) {
    return;
  }
  if ((NSUInteger)index == self.selectedIndex) {
    return;
  }
  self.selectedIndex = (NSUInteger)index;
  if (self.selectionHandler != nil) {
    self.selectionHandler((NSUInteger)index);
  }
}

@end
