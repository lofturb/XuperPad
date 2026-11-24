//
//  XPDetailViewController.m
//

#import "XPDetailViewController.h"
#import "XPPortalClient.h"
#import "XPStreamResolver.h"
#import "XPPlayerViewController.h"
#import "XPTheme.h"
#import "XPButton.h"
#import "XPStatusView.h"
#import "XPImageCache.h"
#import "XPBackControl.h"
#import "XPChipButton.h"
#import "XPDrawnLabel.h"
#import "XPDrawnImageView.h"
#import "XPDrawnScrollView.h"
#import "XPDrawnNavigationController.h"
#import "XPStore.h"

@interface XPEpisodeBadgeView : UIView
@property (nonatomic, copy) NSString *text;
@end

@implementation XPEpisodeBadgeView

- (void)setText:(NSString *)text
{
  _text = [text copy];
  [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect
{
  CGContextRef context = UIGraphicsGetCurrentContext();
  if (context == NULL) {
    return;
  }
  [[XPColorSurfaceAlt() colorWithAlphaComponent:0.92f] setFill];
  [XPRoundedPath(self.bounds, CGRectGetHeight(self.bounds) / 2.0f) fill];

  NSString *text = self.text ?: @"";
  NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
  style.alignment = NSTextAlignmentCenter;
  NSDictionary *attributes = @{ NSFontAttributeName : XPFontCaption(10.5f),
                                NSForegroundColorAttributeName : XPColorAccent(),
                                NSParagraphStyleAttributeName : style };
  CGSize fitted = [text sizeWithAttributes:attributes];
  [text drawInRect:CGRectMake(0,
                              (CGRectGetHeight(self.bounds) - fitted.height) / 2.0f,
                              CGRectGetWidth(self.bounds),
                              fitted.height)
      withAttributes:attributes];
}

@end

@interface XPEpisodeRow : UIView
@property (nonatomic, copy) void (^selectionHandler)(void);
@property (nonatomic, copy) NSString *episodeName;
@property (nonatomic, copy) NSString *episodeNumber;
@property (nonatomic, copy) NSString *episodeDuration;
@property (nonatomic, copy) NSString *imageAddress;
@property (nonatomic, strong) XPDrawnImageView *thumbView;
@property (nonatomic, strong) XPEpisodeBadgeView *badgeView;
@property (nonatomic, strong) XPDrawnLabel *nameLabel;
@property (nonatomic, strong) XPDrawnLabel *durationLabel;
@property (nonatomic, assign) BOOL rowHighlighted;
@end

@implementation XPEpisodeRow

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

    self.badgeView = [[XPEpisodeBadgeView alloc] initWithFrame:CGRectZero];
    self.badgeView.backgroundColor = [UIColor clearColor];
    self.badgeView.opaque = NO;
    self.badgeView.userInteractionEnabled = NO;
    [self.thumbView addSubview:self.badgeView];

    self.nameLabel = [[XPDrawnLabel alloc] initWithFrame:CGRectZero];
    self.nameLabel.font = XPFontBody(13.0f);
    self.nameLabel.textColor = XPColorTextPrimary();
    self.nameLabel.numberOfLines = 2;
    self.nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self addSubview:self.nameLabel];

    self.durationLabel = [[XPDrawnLabel alloc] initWithFrame:CGRectZero];
    self.durationLabel.font = XPFontCaption(10.5f);
    self.durationLabel.textColor = XPColorTextMuted();
    self.durationLabel.numberOfLines = 1;
    [self addSubview:self.durationLabel];
  }
  return self;
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  CGFloat width = CGRectGetWidth(self.bounds);
  CGFloat height = CGRectGetHeight(self.bounds);
  CGFloat thumbWidth = 84.0f;
  CGFloat thumbHeight = 48.0f;
  CGFloat thumbLeft = 14.0f;
  CGFloat thumbTop = (height - thumbHeight) / 2.0f;
  self.thumbView.frame = CGRectMake(thumbLeft, thumbTop, thumbWidth, thumbHeight);
  self.badgeView.frame = CGRectMake(4.0f, thumbHeight - 22.0f, 24.0f, 18.0f);

  CGFloat textLeft = thumbLeft + thumbWidth + 12.0f;
  CGFloat textWidth = MAX(40.0f, width - textLeft - 14.0f);
  self.nameLabel.frame = CGRectMake(textLeft, thumbTop + 4.0f, textWidth, 34.0f);
  self.durationLabel.frame = CGRectMake(textLeft, thumbTop + thumbHeight - 18.0f,
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

- (void)setImageAddress:(NSString *)imageAddress
{
  _imageAddress = [imageAddress copy];
  if (_imageAddress.length == 0) {
    return;
  }
  __weak XPEpisodeRow *weakSelf = self;
  UIImage *cached = [[XPImageCache sharedCache] imageForAddress:_imageAddress];
  if (cached != nil) {
    self.thumbView.image = cached;
    return;
  }
  [[XPImageCache sharedCache] loadImageForAddress:_imageAddress
                                       completion:^(UIImage *image) {
    if (image != nil) {
      weakSelf.thumbView.image = image;
    }
  }];
}

- (void)setEpisodeName:(NSString *)episodeName
{
  _episodeName = [episodeName copy];
  self.nameLabel.text = _episodeName ?: @"";
}

- (void)setEpisodeNumber:(NSString *)episodeNumber
{
  _episodeNumber = [episodeNumber copy];
  self.badgeView.text = _episodeNumber ?: @"";
}

- (void)setEpisodeDuration:(NSString *)episodeDuration
{
  _episodeDuration = [episodeDuration copy];
  self.durationLabel.text = _episodeDuration ?: @"";
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

@interface XPDetailViewController ()
@property (nonatomic, strong) NSDictionary *catalogTitle;
@property (nonatomic, strong) NSDictionary *detailInfo;
@property (nonatomic, strong) NSMutableArray *episodes;
@property (nonatomic, strong) XPDrawnScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) XPDrawnImageView *backdropView;
@property (nonatomic, strong) XPDrawnImageView *posterView;
@property (nonatomic, strong) XPDrawnLabel *titleLabel;
@property (nonatomic, strong) XPDrawnLabel *metaLabel;
@property (nonatomic, strong) XPDrawnLabel *summaryLabel;
@property (nonatomic, strong) XPDrawnLabel *episodesTitleLabel;
@property (nonatomic, strong) XPButton *playButton;
@property (nonatomic, strong) XPButton *favoriteButton;
@property (nonatomic, strong) XPStatusView *statusView;
@property (nonatomic, strong) XPBackControl *backControl;
@property (nonatomic, strong) NSMutableArray *episodeRows;
@property (nonatomic, strong) NSArray *seasons;
@property (nonatomic, copy) NSString *seasonIdentifier;
@property (nonatomic, strong) XPDrawnScrollView *seasonScrollView;
@property (nonatomic, strong) NSMutableArray *seasonChips;
@end

@interface XPDetailViewController ()
- (NSString *)storeId;
- (void)updateFavoriteButton;
- (void)playEpisode:(NSDictionary *)episode resume:(double)resume;
- (void)loadDetailForId:(NSString *)identifier;
- (void)applySeasonChips;
- (void)layoutSeasonChips;
@end

@implementation XPDetailViewController

- (instancetype)initWithTitle:(NSDictionary *)title
{
  self = [super initWithNibName:nil bundle:nil];
  if (self) {
    _catalogTitle = title ?: @{};
    _episodes = [NSMutableArray array];
    _episodeRows = [NSMutableArray array];
    _seasonChips = [NSMutableArray array];
    _seasons = @[];
  }
  return self;
}

- (void)viewDidLoad
{
  [super viewDidLoad];
  self.view.backgroundColor = XPColorBackground();
  self.edgesForExtendedLayout = UIRectEdgeAll;

  [self buildInterface];
  [self loadDetail];
}

- (void)buildInterface
{
  self.scrollView = [[XPDrawnScrollView alloc] initWithFrame:self.view.bounds];
  self.scrollView.backgroundColor = [UIColor clearColor];
  self.scrollView.scrollsVertically = YES;
  self.scrollView.scrollsHorizontally = NO;
  [self.view addSubview:self.scrollView];

  self.contentView = [[UIView alloc] initWithFrame:CGRectZero];
  [self.scrollView addSubview:self.contentView];

  self.backdropView = [[XPDrawnImageView alloc] initWithFrame:CGRectZero];
  self.backdropView.imageMode = XPDrawnImageModeFill;
  self.backdropView.fillColor = XPColorSurface();
  [self.contentView addSubview:self.backdropView];

  self.posterView = [[XPDrawnImageView alloc] initWithFrame:CGRectZero];
  self.posterView.imageMode = XPDrawnImageModeFill;
  self.posterView.fillColor = XPColorSurface();
    self.posterView.cornerRadius = 12.0f;
    self.posterView.borderWidth = 1.0f;
    self.posterView.borderColor = [UIColor colorWithWhite:1.0f alpha:0.12f];
  [self.contentView addSubview:self.posterView];

  self.titleLabel = [[XPDrawnLabel alloc] initWithFrame:CGRectZero];
    self.titleLabel.font = XPFontDisplay(18.0f);
  self.titleLabel.textColor = XPColorTextPrimary();
  self.titleLabel.numberOfLines = 3;
  self.titleLabel.text = self.catalogTitle[@"name"];
  [self.contentView addSubview:self.titleLabel];

  self.metaLabel = [[XPDrawnLabel alloc] initWithFrame:CGRectZero];
  self.metaLabel.font = XPFontCaption(11.0f);
  self.metaLabel.textColor = XPColorAccent();
  self.metaLabel.numberOfLines = 1;
  [self.contentView addSubview:self.metaLabel];

  self.summaryLabel = [[XPDrawnLabel alloc] initWithFrame:CGRectZero];
  self.summaryLabel.font = XPFontBody(12.5f);
  self.summaryLabel.textColor = XPColorTextMuted();
  self.summaryLabel.numberOfLines = 0;
  self.summaryLabel.text = self.catalogTitle[@"summary"];
  [self.contentView addSubview:self.summaryLabel];

  self.playButton = [[XPButton alloc] initWithTitle:@"Reproducir"
                                               style:XPButtonStylePrimary];
  [self.playButton addTarget:self
                       action:@selector(playPrimaryEpisode:)
             forControlEvents:UIControlEventTouchUpInside];
  [self.contentView addSubview:self.playButton];

  self.seasonScrollView = [[XPDrawnScrollView alloc] initWithFrame:CGRectZero];
  self.seasonScrollView.scrollsHorizontally = YES;
  self.seasonScrollView.scrollsVertically = NO;
  self.seasonScrollView.backgroundColor = [UIColor clearColor];
  self.seasonScrollView.hidden = YES;
  [self.contentView addSubview:self.seasonScrollView];

  self.episodesTitleLabel = [[XPDrawnLabel alloc] initWithFrame:CGRectZero];
  self.episodesTitleLabel.font = XPFontMedium(13.0f);
  self.episodesTitleLabel.textColor = XPColorTextPrimary();
  self.episodesTitleLabel.text = @"Episodios";
  [self.contentView addSubview:self.episodesTitleLabel];

  self.backControl = [[XPBackControl alloc] initWithFrame:CGRectZero];
  [self.backControl addTarget:self
                        action:@selector(closeTapped:)
              forControlEvents:UIControlEventTouchUpInside];
  [self.view addSubview:self.backControl];

  self.favoriteButton = [[XPButton alloc] initWithTitle:@"Mi lista"
                                                   style:XPButtonStyleGhost];
  [self.favoriteButton addTarget:self
                          action:@selector(toggleFavorite:)
                forControlEvents:UIControlEventTouchUpInside];
  [self.view addSubview:self.favoriteButton];

  self.statusView = [[XPStatusView alloc] initWithFrame:self.view.bounds];
  self.statusView.backgroundColor = [UIColor clearColor];
  __weak XPDetailViewController *weakSelf = self;
  self.statusView.retryHandler = ^{
    [weakSelf loadDetail];
  };
  [self.view addSubview:self.statusView];
}

- (void)viewDidLayoutSubviews
{
  [super viewDidLayoutSubviews];
  CGFloat width = CGRectGetWidth(self.view.bounds);
  CGFloat height = CGRectGetHeight(self.view.bounds);
  CGFloat margin = 14.0f;
  CGFloat top = 20.0f;

  self.scrollView.frame = CGRectMake(0, 0, width, height);
  self.backControl.frame = CGRectMake(12.0f, top + 6.0f, 34.0f, 34.0f);
  CGFloat favoriteWidth = 104.0f;
  self.favoriteButton.frame = CGRectMake(width - favoriteWidth - 12.0f,
                                         top + 6.0f,
                                         favoriteWidth,
                                         34.0f);
  self.statusView.frame = CGRectMake(0, top + 44.0f, width, MAX(60.0f, height - top - 44.0f));

  CGFloat backdropHeight = 168.0f + top;
  self.backdropView.frame = CGRectMake(0, 0, width, backdropHeight);

  CGFloat posterWidth = 76.0f;
  CGFloat posterHeight = 106.0f;
  CGFloat posterTop = backdropHeight - 46.0f;
  self.posterView.frame = CGRectMake(margin, posterTop, posterWidth, posterHeight);

  CGFloat textLeft = margin + posterWidth + 10.0f;
  CGFloat textWidth = width - textLeft - margin;
  self.titleLabel.frame = CGRectMake(textLeft, posterTop + 2.0f, textWidth, 44.0f);
  self.metaLabel.frame = CGRectMake(textLeft, posterTop + 48.0f, textWidth, 16.0f);

  CGFloat cursor = posterTop + posterHeight + 14.0f;
  self.playButton.frame = CGRectMake(margin, cursor, width - margin * 2.0f, 44.0f);
  cursor += 44.0f + 16.0f;

  if (!self.seasonScrollView.hidden && self.seasonChips.count > 0) {
    self.seasonScrollView.frame = CGRectMake(0, cursor, width, 34.0f);
    [self layoutSeasonChips];
    cursor += 34.0f + 14.0f;
  }

  CGSize summarySize = [self.summaryLabel.text sizeWithAttributes:
                          @{ NSFontAttributeName : XPFontBody(12.5f) }];
  CGFloat summaryHeight = MIN(120.0f, MAX(34.0f, summarySize.height));
  self.summaryLabel.frame = CGRectMake(margin, cursor, width - margin * 2.0f, summaryHeight);
  cursor += summaryHeight + 14.0f;

  self.episodesTitleLabel.frame = CGRectMake(margin, cursor, width - margin * 2.0f, 18.0f);
  cursor += 24.0f;

  for (XPEpisodeRow *row in self.episodeRows) {
    row.frame = CGRectMake(0, cursor, width, 66.0f);
    cursor += 66.0f;
  }
  cursor += 20.0f;

  self.contentView.frame = CGRectMake(0, 0, width, cursor);
  self.scrollView.contentSize = CGSizeMake(width, cursor);
}

- (void)loadDetail
{
  [self loadDetailForId:self.seasonIdentifier ?: self.catalogTitle[@"id"]];
}

- (void)loadDetailForId:(NSString *)contentId
{
  if (contentId.length == 0) {
    [self.statusView showMessage:@"El título no tiene identificador" retry:NO];
    return;
  }
  BOOL isSeries = [self.catalogTitle[@"series"] boolValue];
  [self.statusView showLoading];

  __weak XPDetailViewController *weakSelf = self;
  [[XPPortalClient sharedClient] fetchDetailForTitle:contentId
                                              isSeries:isSeries
                                            completion:^(NSDictionary *detail, NSError *error) {
    if (detail == nil) {
      NSLog(@"[XuperPad] detalle %@ error %@", contentId, error.localizedDescription);
      [weakSelf.statusView showMessage:error.localizedDescription ?: @"No se pudo cargar el título"
                                  retry:YES];
      return;
    }
    NSLog(@"[XuperPad] detalle %@ capitulos %lu temporadas %lu",
          detail[@"name"] ?: contentId,
          (unsigned long)[detail[@"episodes"] count],
          (unsigned long)[detail[@"seasons"] count]);
    [weakSelf.statusView hideStatus];
    weakSelf.seasonIdentifier = contentId;
    NSMutableDictionary *title = [weakSelf.catalogTitle mutableCopy];
    if (title == nil) {
      title = [NSMutableDictionary dictionary];
    }
    title[@"id"] = contentId;
    if ([detail[@"series"] isKindOfClass:[NSNumber class]]) {
      title[@"series"] = detail[@"series"];
    }
    if ([detail[@"poster"] length] > 0) {
      title[@"poster"] = detail[@"poster"];
    }
    if ([detail[@"backdrop"] length] > 0) {
      title[@"backdrop"] = detail[@"backdrop"];
    }
    weakSelf.catalogTitle = title;
    weakSelf.detailInfo = detail;
    weakSelf.episodes = [detail[@"episodes"] mutableCopy] ?: [NSMutableArray array];
    [weakSelf applyDetailToInterface];
    [weakSelf buildEpisodeRows];
    [weakSelf applySeasonChips];
    [weakSelf.view setNeedsLayout];
  }];
}

- (void)applyDetailToInterface
{
  NSDictionary *detail = self.detailInfo;
  NSString *name = detail[@"name"];
  if (name.length > 0) {
    self.titleLabel.text = name;
  }
  self.summaryLabel.text = detail[@"summary"] ?: self.catalogTitle[@"summary"];

  NSMutableArray *parts = [NSMutableArray array];
  NSString *kind = detail[@"kind"];
  if (kind.length > 0) {
    [parts addObject:[kind capitalizedString]];
  }
  NSString *year = detail[@"year"];
  if (year.length > 0) {
    [parts addObject:year];
  }
  NSString *score = detail[@"score"];
  if (score.length > 0) {
    [parts addObject:score];
  }
  NSString *duration = detail[@"duration"];
  if (duration.length > 0) {
    [parts addObject:duration];
  }
  NSArray *genres = detail[@"genres"];
  if ([genres isKindOfClass:[NSArray class]] && genres.count > 0) {
    [parts addObject:[genres componentsJoinedByString:@" · "]];
  }
  self.metaLabel.text = [parts componentsJoinedByString:@"  ·  "];

  [self loadImageForAddress:detail[@"backdrop"] intoView:self.backdropView];
  [self loadImageForAddress:detail[@"poster"] intoView:self.posterView];

  [self updateFavoriteButton];
  NSDictionary *history = [[XPStore sharedStore] historyEntryForId:[self storeId]];
  if (history != nil && [history[@"position"] doubleValue] > 1.0) {
    self.playButton.buttonTitle = @"Continuar";
  } else {
    self.playButton.buttonTitle = @"Reproducir";
  }
}

- (void)applySeasonChips
{
  for (XPChipButton *chip in self.seasonChips) {
    [chip removeFromSuperview];
  }
  [self.seasonChips removeAllObjects];

  NSArray *seasons = [self.detailInfo[@"seasons"] isKindOfClass:[NSArray class]]
                         ? self.detailInfo[@"seasons"] : @[];
  if (![self.detailInfo[@"series"] boolValue] || seasons.count < 2) {
    self.seasons = @[];
    self.seasonScrollView.hidden = YES;
    [self.view setNeedsLayout];
    return;
  }

  self.seasons = seasons;
  for (NSUInteger index = 0; index < seasons.count; index++) {
    id item = seasons[index];
    if (![item isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSDictionary *entry = (NSDictionary *)item;
    NSInteger number = [entry[@"number"] integerValue];
    if (number <= 0) {
      number = (NSInteger)index + 1;
    }
    NSString *title = [NSString stringWithFormat:@"T%ld", (long)number];
    XPChipButton *chip = [[XPChipButton alloc] initWithTitle:title];
    chip.tag = (NSInteger)index;
    NSString *identifier = entry[@"id"];
    chip.selected = (identifier.length > 0 &&
                     [identifier isEqualToString:self.seasonIdentifier]);
    [chip addTarget:self
                  action:@selector(seasonChipTapped:)
        forControlEvents:UIControlEventTouchUpInside];
    [self.seasonScrollView addSubview:chip];
    [self.seasonChips addObject:chip];
  }

  self.seasonScrollView.hidden = self.seasonChips.count < 2;
  [self.view setNeedsLayout];
}

- (void)layoutSeasonChips
{
  CGFloat x = 14.0f;
  CGFloat height = 28.0f;
  for (XPChipButton *chip in self.seasonChips) {
    NSString *title = chip.chipTitle ?: @"";
    CGSize size = [title sizeWithAttributes:@{ NSFontAttributeName : XPFontCaption(11.5f) }];
    CGFloat chipWidth = size.width + 24.0f;
    chip.frame = CGRectMake(x, 3.0f, chipWidth, height);
    x += chipWidth + 8.0f;
  }
  self.seasonScrollView.contentSize = CGSizeMake(x + 4.0f, height + 6.0f);
}

- (void)seasonChipTapped:(XPChipButton *)sender
{
  NSUInteger index = (NSUInteger)sender.tag;
  if (index >= self.seasons.count) {
    return;
  }
  NSDictionary *season = self.seasons[index];
  if (![season isKindOfClass:[NSDictionary class]]) {
    return;
  }
  NSString *identifier = season[@"id"];
  if (identifier.length == 0 || [identifier isEqualToString:self.seasonIdentifier]) {
    return;
  }
  for (XPChipButton *chip in self.seasonChips) {
    chip.selected = (chip == sender);
  }
  self.seasonScrollView.contentOffset = CGPointZero;
  [self loadDetailForId:identifier];
}

- (NSString *)storeId
{
  NSString *identifier = self.catalogTitle[@"id"];
  if (identifier.length == 0) {
    identifier = self.detailInfo[@"id"];
  }
  return identifier ?: @"";
}

- (void)updateFavoriteButton
{
  BOOL favorite = [[XPStore sharedStore] isFavoriteWithId:[self storeId]];
  self.favoriteButton.buttonTitle = favorite ? @"En mi lista" : @"Mi lista";
}

- (void)toggleFavorite:(id)sender
{
  NSString *identifier = [self storeId];
  if (identifier.length == 0) {
    return;
  }
  BOOL series = [self.catalogTitle[@"series"] boolValue];
  if (self.detailInfo[@"series"] != nil) {
    series = [self.detailInfo[@"series"] boolValue];
  }
  NSMutableDictionary *favorite = [NSMutableDictionary dictionary];
  favorite[@"id"] = identifier;
  favorite[@"name"] = self.detailInfo[@"name"] ?: self.catalogTitle[@"name"] ?: @"";
  favorite[@"poster"] = self.detailInfo[@"poster"] ?: self.catalogTitle[@"poster"] ?: @"";
  favorite[@"backdrop"] = self.detailInfo[@"backdrop"] ?: self.catalogTitle[@"backdrop"] ?: @"";
  favorite[@"series"] = @(series);
  favorite[@"kind"] = self.detailInfo[@"kind"] ?: (series ? @"serie" : @"pelA-cula");
  [[XPStore sharedStore] toggleFavoriteWithTitle:favorite];
  [self updateFavoriteButton];
}

- (void)loadImageForAddress:(NSString *)address intoView:(XPDrawnImageView *)view
{
  if (address.length == 0) {
    return;
  }
  UIImage *cached = [[XPImageCache sharedCache] imageForAddress:address];
  if (cached != nil) {
    view.image = cached;
    return;
  }
  __weak XPDrawnImageView *weakView = view;
  [[XPImageCache sharedCache] loadImageForAddress:address
                                       completion:^(UIImage *image) {
    if (image != nil) {
      weakView.image = image;
    }
  }];
}

- (void)buildEpisodeRows
{
  for (XPEpisodeRow *row in self.episodeRows) {
    [row removeFromSuperview];
  }
  [self.episodeRows removeAllObjects];

  NSDictionary *history = [[XPStore sharedStore] historyEntryForId:[self storeId]];
  NSInteger historyChapter = [history[@"chapterIndex"] integerValue];
  double historyPosition = [history[@"position"] doubleValue];
  NSString *fallbackImage = self.detailInfo[@"poster"] ?: self.catalogTitle[@"poster"];

  NSInteger index = -1;
  for (id episode in self.episodes) {
    if (![episode isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    index++;
    NSDictionary *entry = (NSDictionary *)episode;
    XPEpisodeRow *row = [[XPEpisodeRow alloc] initWithFrame:CGRectZero];
    row.episodeName = entry[@"name"];
    row.episodeNumber = [NSString stringWithFormat:@"%@", entry[@"number"] ?: @0];
    NSString *duration = entry[@"duration"];
    row.episodeDuration = duration ?: @"";
    NSString *image = entry[@"image"];
    row.imageAddress = image.length > 0 ? image : (fallbackImage ?: @"");
    BOOL resumable = (history != nil && historyChapter == index && historyPosition > 1.0);
    double resume = resumable ? historyPosition : 0.0;
    __weak XPDetailViewController *weakSelf = self;
    row.selectionHandler = ^{
      [weakSelf playEpisode:entry resume:resume];
    };
    [self.contentView addSubview:row];
    [self.episodeRows addObject:row];
  }

  self.episodesTitleLabel.text = self.episodes.count > 1 ? @"Episodios" : @"Contenido";
}

- (void)playPrimaryEpisode:(id)sender
{
  NSDictionary *history = [[XPStore sharedStore] historyEntryForId:[self storeId]];
  NSInteger chapterIndex = history != nil ? [history[@"chapterIndex"] integerValue] : 0;
  double position = history != nil ? [history[@"position"] doubleValue] : 0.0;

  if (self.episodes.count > 0) {
    if (chapterIndex < 0 || chapterIndex >= (NSInteger)self.episodes.count) {
      chapterIndex = 0;
    }
    id episode = self.episodes[(NSUInteger)chapterIndex];
    if (![episode isKindOfClass:[NSDictionary class]]) {
      episode = self.episodes.firstObject;
      position = 0.0;
    }
    [self playEpisode:episode resume:position];
    return;
  }
  [self playEpisode:@{ @"id" : self.catalogTitle[@"id"] ?: @"",
                        @"name" : self.catalogTitle[@"name"] ?: @"" }
             resume:position];
}

- (void)playEpisode:(NSDictionary *)episode
{
  [self playEpisode:episode resume:0.0];
}

- (void)playEpisode:(NSDictionary *)episode resume:(double)resume
{
  NSString *episodeId = episode[@"id"];
  if (episodeId.length == 0) {
    [self.statusView showMessage:@"El portal no devolvió un capítulo reproducible" retry:NO];
    return;
  }
  NSString *seriesId = self.catalogTitle[@"id"];
  NSString *titleName = self.catalogTitle[@"name"] ?: self.detailInfo[@"name"];

  [self.statusView showLoading];
  __weak XPDetailViewController *weakSelf = self;
  [XPStreamResolver resolveOnDemandForTitle:episodeId
                                   seriesId:seriesId
                                      title:titleName
                                 completion:^(NSDictionary *stream, NSError *error) {
    if (stream == nil) {
      [weakSelf.statusView showMessage:error.localizedDescription ?: @"No se pudo reproducir"
                                  retry:YES];
      return;
    }
    [weakSelf.statusView hideStatus];
    XPPlayerViewController *player = [XPPlayerViewController playerWithStream:stream];
    player.seriesId = seriesId;
    player.seriesName = titleName;
    player.contentId = episodeId;
    player.posterAddress = weakSelf.detailInfo[@"poster"] ?: weakSelf.catalogTitle[@"poster"];
    player.backdropAddress = weakSelf.detailInfo[@"backdrop"] ?: weakSelf.catalogTitle[@"backdrop"];
    player.startPosition = resume;

    NSArray *chapters = [weakSelf.episodes copy] ?: @[];
    NSInteger chapterIndex = 0;
    for (NSUInteger index = 0; index < chapters.count; index++) {
      id item = chapters[index];
      if (![item isKindOfClass:[NSDictionary class]]) {
        continue;
      }
      id candidate = ((NSDictionary *)item)[@"id"];
      if ([candidate isKindOfClass:[NSString class]] &&
          [candidate isEqualToString:episodeId]) {
        chapterIndex = (NSInteger)index;
        break;
      }
    }
    player.chapters = chapters;
    player.currentChapterIndex = chapterIndex;

    [[weakSelf xpNavigationController] pushViewController:player animated:YES];
  }];
}

- (void)closeTapped:(id)sender
{
  [[self xpNavigationController] popViewControllerAnimated:YES];
}

@end
