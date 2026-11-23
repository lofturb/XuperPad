//
//  XPLibraryViewController.m
//

#import "XPLibraryViewController.h"
#import "XPStore.h"
#import "XPTheme.h"
#import "XPDrawnLabel.h"
#import "XPDrawnImageView.h"
#import "XPDrawnScrollView.h"
#import "XPImageCache.h"
#import "XPDetailViewController.h"
#import "XPDrawnNavigationController.h"

@interface XPLibraryRow : UIView
@property (nonatomic, copy) void (^selectionHandler)(void);
@property (nonatomic, strong) XPDrawnImageView *thumbView;
@property (nonatomic, strong) XPDrawnLabel *titleLabel;
@property (nonatomic, strong) XPDrawnLabel *detailLabel;
@property (nonatomic, assign) BOOL rowHighlighted;
@end

@implementation XPLibraryRow

- (instancetype)initWithFrame:(CGRect)frame
{
  self = [super initWithFrame:frame];
  if (self) {
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;

    self.thumbView = [[XPDrawnImageView alloc] initWithFrame:CGRectZero];
    self.thumbView.imageMode = XPDrawnImageModeFill;
    self.thumbView.fillColor = XPColorSurfaceAlt();
    self.thumbView.cornerRadius = 6.0f;
    self.thumbView.borderWidth = 1.0f;
    self.thumbView.borderColor = [UIColor colorWithWhite:1.0f alpha:0.08f];
    [self addSubview:self.thumbView];

    self.titleLabel = [[XPDrawnLabel alloc] initWithFrame:CGRectZero];
    self.titleLabel.font = XPFontBody(14.0f);
    self.titleLabel.textColor = XPColorTextPrimary();
    self.titleLabel.numberOfLines = 2;
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self addSubview:self.titleLabel];

    self.detailLabel = [[XPDrawnLabel alloc] initWithFrame:CGRectZero];
    self.detailLabel.font = XPFontCaption(10.5f);
    self.detailLabel.textColor = XPColorTextMuted();
    self.detailLabel.numberOfLines = 1;
    [self addSubview:self.detailLabel];
  }
  return self;
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  CGFloat height = CGRectGetHeight(self.bounds);
  CGFloat width = CGRectGetWidth(self.bounds);
  CGFloat thumbWidth = 96.0f;
  CGFloat thumbHeight = 56.0f;
  CGFloat thumbLeft = 14.0f;
  CGFloat thumbTop = (height - thumbHeight) / 2.0f;
  self.thumbView.frame = CGRectMake(thumbLeft, thumbTop, thumbWidth, thumbHeight);

  CGFloat textLeft = thumbLeft + thumbWidth + 12.0f;
  CGFloat textWidth = MAX(40.0f, width - textLeft - 14.0f);
  self.titleLabel.frame = CGRectMake(textLeft, thumbTop + 2.0f, textWidth, 38.0f);
  self.detailLabel.frame = CGRectMake(textLeft, thumbTop + thumbHeight - 16.0f,
                                      textWidth, 14.0f);
}

- (void)drawRect:(CGRect)rect
{
  CGContextRef context = UIGraphicsGetCurrentContext();
  if (context == NULL) {
    return;
  }
  CGRect card = CGRectInset(self.bounds, 8.0f, 3.0f);
  CGFloat alpha = self.rowHighlighted ? 0.95f : 0.55f;
  [[XPColorSurfaceAlt() colorWithAlphaComponent:alpha] setFill];
  [XPRoundedPath(card, 12.0f) fill];
}

- (void)setRowHighlighted:(BOOL)rowHighlighted
{
  _rowHighlighted = rowHighlighted;
  self.alpha = rowHighlighted ? 0.7f : 1.0f;
  [self setNeedsDisplay];
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
  self.rowHighlighted = YES;
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
  self.rowHighlighted = NO;
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
  self.rowHighlighted = NO;
  if (self.selectionHandler != nil) {
    self.selectionHandler();
  }
}

@end

@interface XPLibraryViewController ()
@property (nonatomic, strong) XPDrawnScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) XPDrawnLabel *headerLabel;
@property (nonatomic, strong) XPDrawnLabel *historyHeader;
@property (nonatomic, strong) XPDrawnLabel *favoritesHeader;
@property (nonatomic, strong) XPDrawnLabel *emptyLabel;
@property (nonatomic, strong) NSMutableArray *rows;
@end

@implementation XPLibraryViewController

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
  self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
  if (self) {
    _rows = [NSMutableArray array];
  }
  return self;
}

- (void)viewDidLoad
{
  [super viewDidLoad];
  self.view.backgroundColor = XPColorBackground();
  self.edgesForExtendedLayout = UIRectEdgeAll;

  self.scrollView = [[XPDrawnScrollView alloc] initWithFrame:self.view.bounds];
  self.scrollView.backgroundColor = [UIColor clearColor];
  self.scrollView.scrollsVertically = YES;
  self.scrollView.scrollsHorizontally = NO;
  [self.view addSubview:self.scrollView];

  self.contentView = [[UIView alloc] initWithFrame:CGRectZero];
  [self.scrollView addSubview:self.contentView];

  self.headerLabel = [[XPDrawnLabel alloc] initWithFrame:CGRectZero];
  self.headerLabel.font = XPFontDisplay(22.0f);
  self.headerLabel.textColor = XPColorTextPrimary();
  self.headerLabel.text = self.screenTitle ?: @"Mi lista";
  [self.contentView addSubview:self.headerLabel];

  self.historyHeader = [[XPDrawnLabel alloc] initWithFrame:CGRectZero];
  self.historyHeader.font = XPFontMedium(15.0f);
  self.historyHeader.textColor = XPColorTextPrimary();
  self.historyHeader.text = @"Continuar viendo";
  [self.contentView addSubview:self.historyHeader];

  self.favoritesHeader = [[XPDrawnLabel alloc] initWithFrame:CGRectZero];
  self.favoritesHeader.font = XPFontMedium(15.0f);
  self.favoritesHeader.textColor = XPColorTextPrimary();
  self.favoritesHeader.text = @"Guardados";
  [self.contentView addSubview:self.favoritesHeader];

  self.emptyLabel = [[XPDrawnLabel alloc] initWithFrame:CGRectZero];
  self.emptyLabel.font = XPFontBody(13.0f);
  self.emptyLabel.textColor = XPColorTextMuted();
  self.emptyLabel.numberOfLines = 0;
  self.emptyLabel.text = @"Reproduce algo y aparecera aqui.";
  [self.contentView addSubview:self.emptyLabel];
}

- (void)viewWillAppear:(BOOL)animated
{
  [super viewWillAppear:animated];
  [self reloadContent];
}

- (NSString *)detailTextForEntry:(NSDictionary *)entry
{
  double position = [entry[@"position"] doubleValue];
  double duration = [entry[@"duration"] doubleValue];
  NSInteger percent = 0;
  if (duration > 0.0) {
    percent = (NSInteger)((position / duration) * 100.0);
  }
  percent = MAX(0, MIN(100, percent));
  BOOL series = [entry[@"series"] boolValue];
  if (series) {
    NSInteger chapter = [entry[@"chapterIndex"] integerValue] + 1;
    return [NSString stringWithFormat:@"Cap %ld - %ld%% visto", (long)chapter, (long)percent];
  }
  return [NSString stringWithFormat:@"%ld%% visto", (long)percent];
}

- (void)addRowForTitle:(NSDictionary *)title
                  name:(NSString *)name
                detail:(NSString *)detail
               artwork:(NSString *)artwork
{
  XPLibraryRow *row = [[XPLibraryRow alloc] initWithFrame:CGRectZero];
  row.titleLabel.text = name ?: @"";
  row.detailLabel.text = detail ?: @"";
  if (artwork.length > 0) {
    __weak XPLibraryRow *weakRow = row;
    UIImage *cached = [[XPImageCache sharedCache] imageForAddress:artwork];
    if (cached != nil) {
      row.thumbView.image = cached;
    } else {
      [[XPImageCache sharedCache] loadImageForAddress:artwork
                                           completion:^(UIImage *image) {
        if (image != nil) {
          weakRow.thumbView.image = image;
        }
      }];
    }
  }
  NSDictionary *info = [title copy];
  __weak XPLibraryViewController *weakSelf = self;
  row.selectionHandler = ^{
    XPDetailViewController *detailController = [[XPDetailViewController alloc] initWithTitle:info];
    [[weakSelf xpNavigationController] pushViewController:detailController animated:YES];
  };
  [self.contentView addSubview:row];
  [self.rows addObject:row];
}

- (void)reloadContent
{
  for (XPLibraryRow *row in self.rows) {
    [row removeFromSuperview];
  }
  [self.rows removeAllObjects];

  NSArray *history = [[XPStore sharedStore] historyEntries];
  NSArray *favorites = [[XPStore sharedStore] favoriteTitles];

  NSInteger historyCount = 0;
  for (id item in history) {
    if (![item isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSDictionary *entry = (NSDictionary *)item;
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[@"id"] = entry[@"id"] ?: @"";
    info[@"name"] = entry[@"name"] ?: @"";
    info[@"poster"] = entry[@"poster"] ?: @"";
    info[@"backdrop"] = entry[@"backdrop"] ?: @"";
    info[@"series"] = entry[@"series"] ?: @NO;
    info[@"summary"] = @"";
    NSString *artwork = entry[@"poster"];
    if (artwork.length == 0) {
      artwork = entry[@"backdrop"];
    }
    [self addRowForTitle:info
                    name:entry[@"name"]
                  detail:[self detailTextForEntry:entry]
                 artwork:artwork];
    historyCount++;
  }

  NSInteger favoriteCount = 0;
  for (id item in favorites) {
    if (![item isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSDictionary *entry = (NSDictionary *)item;
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[@"id"] = entry[@"id"] ?: @"";
    info[@"name"] = entry[@"name"] ?: @"";
    info[@"poster"] = entry[@"poster"] ?: @"";
    info[@"backdrop"] = entry[@"backdrop"] ?: @"";
    info[@"series"] = entry[@"series"] ?: @NO;
    info[@"summary"] = @"";
    NSString *artwork = entry[@"poster"];
    if (artwork.length == 0) {
      artwork = entry[@"backdrop"];
    }
    BOOL series = [entry[@"series"] boolValue];
    [self addRowForTitle:info
                    name:entry[@"name"]
                  detail:(series ? @"Serie" : @"Pelicula")
                 artwork:artwork];
    favoriteCount++;
  }

  self.historyHeader.hidden = historyCount == 0;
  self.favoritesHeader.hidden = favoriteCount == 0;
  self.emptyLabel.hidden = (historyCount + favoriteCount) > 0;

  [self.view setNeedsLayout];
}

- (void)viewDidLayoutSubviews
{
  [super viewDidLayoutSubviews];
  CGFloat width = CGRectGetWidth(self.view.bounds);
  CGFloat height = CGRectGetHeight(self.view.bounds);
  CGFloat margin = 14.0f;

  self.scrollView.frame = CGRectMake(0, 0, width, height);

  CGFloat cursor = 24.0f;
  self.headerLabel.frame = CGRectMake(margin, cursor, width - margin * 2.0f, 28.0f);
  cursor += 40.0f;

  self.historyHeader.frame = CGRectMake(margin, cursor, width - margin * 2.0f, 20.0f);
  cursor += 26.0f;

  NSInteger historyCount = [[[XPStore sharedStore] historyEntries] count];
  NSInteger favoriteCount = [[[XPStore sharedStore] favoriteTitles] count];
  NSInteger historyRows = MIN((NSInteger)self.rows.count, historyCount);
  for (NSInteger index = 0; index < historyRows; index++) {
    XPLibraryRow *row = self.rows[(NSUInteger)index];
    row.frame = CGRectMake(0, cursor, width, 72.0f);
    cursor += 72.0f;
  }
  if (historyCount > 0) {
    cursor += 10.0f;
  }

  self.favoritesHeader.frame = CGRectMake(margin, cursor, width - margin * 2.0f, 20.0f);
  cursor += 26.0f;

  for (NSInteger index = historyRows; index < (NSInteger)self.rows.count; index++) {
    XPLibraryRow *row = self.rows[(NSUInteger)index];
    row.frame = CGRectMake(0, cursor, width, 72.0f);
    cursor += 72.0f;
  }

  self.emptyLabel.frame = CGRectMake(margin, 96.0f, width - margin * 2.0f, 40.0f);
  if (favoriteCount == 0 && historyCount == 0) {
    self.emptyLabel.hidden = NO;
  }

  cursor += 24.0f;
  self.contentView.frame = CGRectMake(0, 0, width, cursor);
  self.scrollView.contentSize = CGSizeMake(width, cursor);
}

@end
