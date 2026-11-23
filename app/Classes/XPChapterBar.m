#import "XPChapterBar.h"

#import "XPButton.h"
#import "XPChipButton.h"
#import "XPTheme.h"
#import "XPDrawnLabel.h"
#import "XPDrawnScrollView.h"

@interface XPChapterBar ()
@property (nonatomic, strong) XPDrawnLabel *positionLabel;
@property (nonatomic, strong) XPButton *previousButton;
@property (nonatomic, strong) XPButton *nextButton;
@property (nonatomic, strong) XPDrawnScrollView *scrollView;
@property (nonatomic, strong) NSMutableArray *chipButtons;
@end

@implementation XPChapterBar

- (instancetype)initWithFrame:(CGRect)frame
{
  self = [super initWithFrame:frame];
  if (self) {
    self.backgroundColor = [XPColorSurface() colorWithAlphaComponent:0.92f];
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;

    self.chipButtons = [NSMutableArray array];

    self.previousButton = [[XPButton alloc] initWithTitle:@"‹ Anterior"
                                                    style:XPButtonStyleGhost];
    [self.previousButton addTarget:self
                             action:@selector(previousTapped:)
                   forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.previousButton];

    self.positionLabel = [[XPDrawnLabel alloc] initWithFrame:CGRectZero];
    self.positionLabel.font = XPFontCaption(11.5f);
    self.positionLabel.textColor = XPColorTextPrimary();
    self.positionLabel.textAlignment = NSTextAlignmentCenter;
    self.positionLabel.text = @"";
    [self addSubview:self.positionLabel];

    self.nextButton = [[XPButton alloc] initWithTitle:@"Siguiente ›"
                                                style:XPButtonStyleGhost];
    [self.nextButton addTarget:self
                         action:@selector(nextTapped:)
               forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.nextButton];

    self.scrollView = [[XPDrawnScrollView alloc] initWithFrame:CGRectZero];
    self.scrollView.scrollsHorizontally = YES;
    self.scrollView.scrollsVertically = NO;
    [self addSubview:self.scrollView];

    self.currentIndex = 0;
  }
  return self;
}

- (void)setChapters:(NSArray *)chapters
{
  _chapters = [chapters copy];
  [self rebuildChips];
}

- (void)setCurrentIndex:(NSInteger)currentIndex
{
  _currentIndex = currentIndex;
  [self updateChipSelection];
  [self updatePositionLabel];
}

- (NSString *)titleForChapter:(NSDictionary *)chapter atIndex:(NSInteger)index
{
  id name = chapter[@"name"];
  if ([name isKindOfClass:[NSString class]] && [name length] > 0) {
    return (NSString *)name;
  }
  id number = chapter[@"number"];
  if ([number isKindOfClass:[NSNumber class]] && [number integerValue] > 0) {
    return [NSString stringWithFormat:@"Capítulo %ld", (long)[number integerValue]];
  }
  return [NSString stringWithFormat:@"Capítulo %ld", (long)(index + 1)];
}

- (void)rebuildChips
{
  for (XPChipButton *chip in self.chipButtons) {
    [chip removeFromSuperview];
  }
  [self.chipButtons removeAllObjects];

  CGFloat offset = 0.0f;
  NSInteger index = 0;
  for (id item in self.chapters) {
    if (![item isKindOfClass:[NSDictionary class]]) {
      index++;
      continue;
    }
    NSDictionary *chapter = (NSDictionary *)item;
    NSString *title = [self titleForChapter:chapter atIndex:index];
    XPChipButton *chip = [[XPChipButton alloc] initWithTitle:title];
    chip.tag = index;
    [chip addTarget:self
              action:@selector(chipTapped:)
    forControlEvents:UIControlEventTouchUpInside];
    NSDictionary *attributes = @{ NSFontAttributeName : XPFontCaption(11.5f) };
    CGSize fitted = [title sizeWithAttributes:attributes];
    CGFloat chipWidth = MAX(64.0f, fitted.width + 26.0f);
    chip.frame = CGRectMake(offset, 2.0f, chipWidth, 30.0f);
    [self.scrollView addSubview:chip];
    [self.chipButtons addObject:chip];
    offset += chipWidth + 8.0f;
    index++;
  }

  self.scrollView.contentSize = CGSizeMake(MAX(1.0f, offset), 34.0f);
  [self updateChipSelection];
  [self updatePositionLabel];
  [self setNeedsLayout];
}

- (void)updateChipSelection
{
  for (XPChipButton *chip in self.chipButtons) {
    chip.selected = (chip.tag == self.currentIndex);
  }
}

- (void)updatePositionLabel
{
  NSInteger total = (NSInteger)self.chapters.count;
  if (total <= 0) {
    self.positionLabel.text = @"";
    return;
  }
  NSInteger current = self.currentIndex + 1;
  if (current < 1) {
    current = 1;
  }
  if (current > total) {
    current = total;
  }
  self.positionLabel.text = [NSString stringWithFormat:@"Cap. %ld de %ld",
                             (long)current,
                             (long)total];
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  CGFloat width = CGRectGetWidth(self.bounds);
  CGFloat height = CGRectGetHeight(self.bounds);
  CGFloat margin = 10.0f;

  self.previousButton.frame = CGRectMake(margin, 6.0f, 88.0f, 28.0f);
  self.nextButton.frame = CGRectMake(width - margin - 88.0f, 6.0f, 88.0f, 28.0f);
  CGFloat labelLeft = margin + 92.0f;
  CGFloat labelWidth = MAX(40.0f, width - labelLeft * 2.0f - 4.0f);
  self.positionLabel.frame = CGRectMake(labelLeft, 12.0f, labelWidth, 16.0f);
  self.scrollView.frame = CGRectMake(margin, 38.0f, width - margin * 2.0f, 36.0f);
}

- (void)drawRect:(CGRect)rect
{
  CGContextRef context = UIGraphicsGetCurrentContext();
  if (context == NULL) {
    return;
  }
  [XPColorDivider() setFill];
  CGContextFillRect(context, CGRectMake(0.0f, 0.0f, CGRectGetWidth(self.bounds), 1.0f));
}

- (void)previousTapped:(id)sender
{
  if (self.previousHandler != nil) {
    self.previousHandler();
  }
}

- (void)nextTapped:(id)sender
{
  if (self.nextHandler != nil) {
    self.nextHandler();
  }
}

- (void)chipTapped:(id)sender
{
  XPChipButton *chip = (XPChipButton *)sender;
  if (self.selectionHandler != nil) {
    self.selectionHandler(chip.tag);
  }
}

@end
