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

@interface XPEpisodeRow : UIView
@property (nonatomic, copy) void (^selectionHandler)(void);
@property (nonatomic, strong) NSString *episodeName;
@property (nonatomic, copy) NSString *episodeNumber;
@property (nonatomic, copy) NSString *episodeDuration;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *durationLabel;
@end

@implementation XPEpisodeRow

- (instancetype)initWithFrame:(CGRect)frame
{
  self = [super initWithFrame:frame];
  if (self) {
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;

    self.nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.nameLabel.font = XPFontBody(12.5f);
    self.nameLabel.textColor = XPColorTextPrimary();
    self.nameLabel.numberOfLines = 1;
    self.nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self addSubview:self.nameLabel];

    self.durationLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.durationLabel.font = XPFontCaption(10.5f);
    self.durationLabel.textColor = XPColorTextMuted();
    self.durationLabel.textAlignment = NSTextAlignmentRight;
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
  CGFloat durationWidth = 46.0f;
  self.nameLabel.frame = CGRectMake(46.0f, (height - 16.0f) / 2.0f,
                                    MAX(20.0f, width - 46.0f - durationWidth - 16.0f),
                                    16.0f);
  self.durationLabel.frame = CGRectMake(width - durationWidth - 12.0f,
                                        (height - 14.0f) / 2.0f,
                                        durationWidth,
                                        14.0f);
}

- (void)drawRect:(CGRect)rect
{
  CGContextRef context = UIGraphicsGetCurrentContext();
  if (context == NULL) {
    return;
  }
  CGFloat badgeSide = 26.0f;
  CGRect badge = CGRectMake(12.0f,
                            (CGRectGetHeight(self.bounds) - badgeSide) / 2.0f,
                            badgeSide,
                            badgeSide);
  [[XPColorSurfaceAlt() colorWithAlphaComponent:0.95f] setFill];
  [XPRoundedPath(badge, badgeSide / 2.0f) fill];

  NSString *number = self.episodeNumber ?: @"";
  NSDictionary *attributes = @{ NSFontAttributeName : XPFontCaption(11.0f),
                                NSForegroundColorAttributeName : XPColorAccent() };
  NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
  style.alignment = NSTextAlignmentCenter;
  NSMutableDictionary *finalAttributes = [attributes mutableCopy];
  [finalAttributes setObject:style forKey:NSParagraphStyleAttributeName];
  CGSize fitted = [number sizeWithAttributes:finalAttributes];
  [number drawInRect:CGRectMake(CGRectGetMinX(badge),
                                CGRectGetMidY(badge) - fitted.height / 2.0f,
                                badgeSide,
                                fitted.height)
      withAttributes:finalAttributes];
}

- (void)setEpisodeName:(NSString *)episodeName
{
  _episodeName = [episodeName copy];
  self.nameLabel.text = _episodeName ?: @"";
}

- (void)setEpisodeNumber:(NSString *)episodeNumber
{
  _episodeNumber = [episodeNumber copy];
  [self setNeedsDisplay];
}

- (void)setEpisodeDuration:(NSString *)episodeDuration
{
  _episodeDuration = [episodeDuration copy];
  self.durationLabel.text = _episodeDuration ?: @"";
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
  if (self.selectionHandler != nil) {
    self.selectionHandler();
  }
}

@end

@interface XPDetailViewController ()
@property (nonatomic, strong) NSDictionary *catalogTitle;
@property (nonatomic, strong) NSDictionary *detailInfo;
@property (nonatomic, strong) NSMutableArray *episodes;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIImageView *backdropView;
@property (nonatomic, strong) UIImageView *posterView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) UILabel *summaryLabel;
@property (nonatomic, strong) UILabel *episodesTitleLabel;
@property (nonatomic, strong) XPButton *playButton;
@property (nonatomic, strong) XPStatusView *statusView;
@property (nonatomic, strong) XPBackControl *backControl;
@property (nonatomic, strong) NSMutableArray *episodeRows;
@end

@implementation XPDetailViewController

- (instancetype)initWithTitle:(NSDictionary *)title
{
  self = [super initWithNibName:nil bundle:nil];
  if (self) {
    _catalogTitle = title ?: @{};
    _episodes = [NSMutableArray array];
    _episodeRows = [NSMutableArray array];
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
  self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
  self.scrollView.backgroundColor = [UIColor clearColor];
  self.scrollView.showsVerticalScrollIndicator = NO;
  self.scrollView.alwaysBounceVertical = YES;
  [self.view addSubview:self.scrollView];

  self.contentView = [[UIView alloc] initWithFrame:CGRectZero];
  [self.scrollView addSubview:self.contentView];

  self.backdropView = [[UIImageView alloc] initWithFrame:CGRectZero];
  self.backdropView.contentMode = UIViewContentModeScaleAspectFill;
  self.backdropView.clipsToBounds = YES;
  self.backdropView.backgroundColor = XPColorSurface();
  [self.contentView addSubview:self.backdropView];

  self.posterView = [[UIImageView alloc] initWithFrame:CGRectZero];
  self.posterView.contentMode = UIViewContentModeScaleAspectFill;
  self.posterView.clipsToBounds = YES;
  self.posterView.backgroundColor = XPColorSurface();
  self.posterView.layer.cornerRadius = 8.0f;
  self.posterView.layer.borderWidth = 1.0f;
  self.posterView.layer.borderColor = [XPColorDivider() CGColor];
  [self.contentView addSubview:self.posterView];

  self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
  self.titleLabel.font = XPFontDisplay(16.0f);
  self.titleLabel.textColor = XPColorTextPrimary();
  self.titleLabel.numberOfLines = 3;
  self.titleLabel.text = self.catalogTitle[@"name"];
  [self.contentView addSubview:self.titleLabel];

  self.metaLabel = [[UILabel alloc] initWithFrame:CGRectZero];
  self.metaLabel.font = XPFontCaption(11.0f);
  self.metaLabel.textColor = XPColorAccent();
  self.metaLabel.numberOfLines = 1;
  [self.contentView addSubview:self.metaLabel];

  self.summaryLabel = [[UILabel alloc] initWithFrame:CGRectZero];
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

  self.episodesTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
  self.episodesTitleLabel.font = XPFontMedium(13.0f);
  self.episodesTitleLabel.textColor = XPColorTextPrimary();
  self.episodesTitleLabel.text = @"Episodios";
  [self.contentView addSubview:self.episodesTitleLabel];

  self.backControl = [[XPBackControl alloc] initWithFrame:CGRectZero];
  [self.backControl addTarget:self
                        action:@selector(closeTapped:)
              forControlEvents:UIControlEventTouchUpInside];
  [self.view addSubview:self.backControl];

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

  CGSize summarySize = [self.summaryLabel.text sizeWithAttributes:
                          @{ NSFontAttributeName : XPFontBody(12.5f) }];
  CGFloat summaryHeight = MIN(120.0f, MAX(34.0f, summarySize.height));
  self.summaryLabel.frame = CGRectMake(margin, cursor, width - margin * 2.0f, summaryHeight);
  cursor += summaryHeight + 14.0f;

  self.episodesTitleLabel.frame = CGRectMake(margin, cursor, width - margin * 2.0f, 18.0f);
  cursor += 24.0f;

  for (XPEpisodeRow *row in self.episodeRows) {
    row.frame = CGRectMake(0, cursor, width, 44.0f);
    cursor += 44.0f;
  }
  cursor += 20.0f;

  self.contentView.frame = CGRectMake(0, 0, width, cursor);
  self.scrollView.contentSize = CGSizeMake(width, cursor);
}

- (void)loadDetail
{
  NSString *contentId = self.catalogTitle[@"id"];
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
    NSLog(@"[XuperPad] detalle %@ capitulos %lu",
          detail[@"name"] ?: contentId,
          (unsigned long)[detail[@"episodes"] count]);
    [weakSelf.statusView hideStatus];
    weakSelf.detailInfo = detail;
    weakSelf.episodes = [detail[@"episodes"] mutableCopy] ?: [NSMutableArray array];
    [weakSelf applyDetailToInterface];
    [weakSelf buildEpisodeRows];
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
}

- (void)loadImageForAddress:(NSString *)address intoView:(UIImageView *)view
{
  if (address.length == 0) {
    return;
  }
  UIImage *cached = [[XPImageCache sharedCache] imageForAddress:address];
  if (cached != nil) {
    view.image = cached;
    return;
  }
  __weak UIImageView *weakView = view;
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

  for (id episode in self.episodes) {
    if (![episode isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSDictionary *entry = (NSDictionary *)episode;
    XPEpisodeRow *row = [[XPEpisodeRow alloc] initWithFrame:CGRectZero];
    row.episodeName = entry[@"name"];
    row.episodeNumber = [NSString stringWithFormat:@"%@", entry[@"number"] ?: @0];
    NSString *duration = entry[@"duration"];
    row.episodeDuration = duration ?: @"";
    __weak XPDetailViewController *weakSelf = self;
    row.selectionHandler = ^{
      [weakSelf playEpisode:entry];
    };
    [self.contentView addSubview:row];
    [self.episodeRows addObject:row];
  }

  self.episodesTitleLabel.text = self.episodes.count > 1 ? @"Episodios" : @"Contenido";
}

- (void)playPrimaryEpisode:(id)sender
{
  if (self.episodes.count > 0) {
    [self playEpisode:self.episodes.firstObject];
    return;
  }
  [self playEpisode:@{ @"id" : self.catalogTitle[@"id"] ?: @"",
                        @"name" : self.catalogTitle[@"name"] ?: @"" }];
}

- (void)playEpisode:(NSDictionary *)episode
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
    [weakSelf.navigationController pushViewController:player animated:YES];
  }];
}

- (void)closeTapped:(id)sender
{
  [self.navigationController popViewControllerAnimated:YES];
}

@end
