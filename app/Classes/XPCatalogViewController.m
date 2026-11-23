//
//  XPCatalogViewController.m
//

#import "XPCatalogViewController.h"
#import "XPConstants.h"
#import "XPPortalClient.h"
#import "XPCardCell.h"
#import "XPSectionHeaderView.h"
#import "XPDetailViewController.h"
#import "XPStreamResolver.h"
#import "XPPlayerViewController.h"
#import "XPTheme.h"
#import "XPSearchField.h"
#import "XPChipButton.h"
#import "XPStatusView.h"
#import "XPDrawnLabel.h"
#import "XPDrawnScrollView.h"
#import "XPDrawnCollectionView.h"
#import "XPDrawnNavigationController.h"

static NSString *const XPCellIdentifier = @"XPCardCell";
static NSString *const XPSectionIdentifier = @"XPSectionHeader";

@interface XPCatalogViewController () <XPDrawnCollectionViewDataSource, XPDrawnCollectionViewDelegate>
@property (nonatomic, strong) XPDrawnLabel *titleLabel;
@property (nonatomic, strong) XPDrawnLabel *brandLabel;
@property (nonatomic, strong) XPSearchField *searchField;
@property (nonatomic, strong) XPDrawnScrollView *chipsScrollView;
@property (nonatomic, strong) NSMutableArray *chipButtons;
@property (nonatomic, strong) XPDrawnCollectionView *collectionView;
@property (nonatomic, strong) XPStatusView *statusView;
@property (nonatomic, strong) NSMutableArray *sections;
@property (nonatomic, copy) NSString *activeColumnCode;
@property (nonatomic, assign) NSUInteger currentPage;
@property (nonatomic, assign) BOOL loadingMore;
@property (nonatomic, assign) BOOL searching;
@property (nonatomic, copy) NSString *searchText;
@property (nonatomic, copy) NSString *searchFilter;
@property (nonatomic, copy) NSArray *liveCategories;
@end

@implementation XPCatalogViewController

- (void)viewDidLoad
{
  [super viewDidLoad];
  self.view.backgroundColor = XPColorBackground();
  self.edgesForExtendedLayout = UIRectEdgeAll;
  self.sections = [NSMutableArray array];
  self.chipButtons = [NSMutableArray array];
  self.currentPage = 1;
  self.searchFilter = @"all";

  [self buildInterface];

  if (self.showsLiveChannels) {
    [self loadLiveCategories];
  } else {
    [self applyBrowseChips];
    [self loadCatalogForColumn:XPColumnFeatured];
  }
}

- (void)buildInterface
{
  self.brandLabel = [[XPDrawnLabel alloc] initWithFrame:CGRectZero];
  self.brandLabel.font = [UIFont systemFontOfSize:9.5f weight:UIFontWeightBold];
  self.brandLabel.textColor = XPColorAccent();
  self.brandLabel.text = @"XUPER TV";
  [self.view addSubview:self.brandLabel];

  self.titleLabel = [[XPDrawnLabel alloc] initWithFrame:CGRectZero];
  self.titleLabel.font = XPFontDisplay(22.0f);
  self.titleLabel.textColor = XPColorTextPrimary();
  self.titleLabel.text = self.screenTitle ?: @"Catálogo";
  [self.view addSubview:self.titleLabel];

  if (!self.showsLiveChannels) {
    self.searchField = [[XPSearchField alloc] initWithHint:@"Buscar películas, series, anime..."];
    __weak XPCatalogViewController *weakSelf = self;
    self.searchField.searchHandler = ^(NSString *text) {
      [weakSelf handleSearchText:text];
    };
    self.searchField.clearHandler = ^{
      [weakSelf exitSearchMode];
    };
    [self.view addSubview:self.searchField];
  }

  self.chipsScrollView = [[XPDrawnScrollView alloc] initWithFrame:CGRectZero];
  self.chipsScrollView.scrollsHorizontally = YES;
  self.chipsScrollView.scrollsVertically = NO;
  self.chipsScrollView.backgroundColor = [UIColor clearColor];
  [self.view addSubview:self.chipsScrollView];

  self.collectionView = [[XPDrawnCollectionView alloc] initWithFrame:self.view.bounds];
  self.collectionView.backgroundColor = [UIColor clearColor];
  self.collectionView.dataSource = self;
  self.collectionView.delegate = self;
  self.collectionView.itemAspect = 1.45f;
  [self.collectionView registerCellClass:[XPCardCell class]
                     forReuseIdentifier:XPCellIdentifier];
  [self.collectionView registerSupplementaryClass:[XPSectionHeaderView class]
                                   forElementKind:UICollectionElementKindSectionHeader
                               withReuseIdentifier:XPSectionIdentifier];
  [self.view addSubview:self.collectionView];

  self.statusView = [[XPStatusView alloc] initWithFrame:self.view.bounds];
  self.statusView.backgroundColor = [UIColor clearColor];
  __weak XPCatalogViewController *weakSelf = self;
  self.statusView.retryHandler = ^{
    [weakSelf retryCurrentLoad];
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

  self.brandLabel.frame = CGRectMake(margin, top + 7.0f, width - margin * 2.0f, 12.0f);
  self.titleLabel.frame = CGRectMake(margin, top + 23.0f, width - margin * 2.0f, 28.0f);

  CGFloat chipsTop = top + 56.0f;
  if (self.searchField != nil) {
    self.searchField.frame = CGRectMake(margin, top + 56.0f, width - margin * 2.0f, 36.0f);
    chipsTop = top + 100.0f;
  }

  self.chipsScrollView.frame = CGRectMake(0, chipsTop, width, 34.0f);
  [self layoutChips];

  CGFloat gridTop = chipsTop + 38.0f;
  self.collectionView.frame = CGRectMake(0, gridTop, width, MAX(60.0f, height - gridTop));
  self.statusView.frame = CGRectMake(0, gridTop, width, MAX(60.0f, height - gridTop));

  [self updateCollectionItemSize];
}

- (void)updateCollectionItemSize
{
  CGFloat width = CGRectGetWidth(self.collectionView.bounds);
  if (width <= 0) {
    return;
  }
  NSUInteger columns = 3;
  if (width >= 620.0f) {
    columns = 5;
  } else if (width >= 460.0f) {
    columns = 4;
  }
  CGFloat spacing = 8.0f;
  CGFloat insets = 24.0f;
  CGFloat itemWidth = floor((width - insets - spacing * (CGFloat)(columns - 1)) / (CGFloat)columns);
  if (itemWidth < 40.0f) {
    itemWidth = 40.0f;
  }
  CGFloat itemHeight = floor(itemWidth * 1.5f) + 32.0f;
  if (fabs(self.collectionView.itemSize.width - itemWidth) > 0.5f ||
      fabs(self.collectionView.itemSize.height - itemHeight) > 0.5f ||
      self.collectionView.columns != (NSInteger)columns) {
    self.collectionView.columns = (NSInteger)columns;
    self.collectionView.itemSize = CGSizeMake(itemWidth, itemHeight);
  }
}

- (void)layoutChips
{
  CGFloat x = 12.0f;
  CGFloat height = 28.0f;
  for (XPChipButton *chip in self.chipButtons) {
    NSString *title = chip.chipTitle ?: @"";
    CGSize size = [title sizeWithAttributes:@{ NSFontAttributeName : XPFontCaption(11.5f) }];
    CGFloat chipWidth = size.width + 24.0f;
    chip.frame = CGRectMake(x, 3.0f, chipWidth, height);
    x += chipWidth + 8.0f;
  }
  self.chipsScrollView.contentSize = CGSizeMake(x + 4.0f, height + 6.0f);
}

- (void)applyChips:(NSArray *)definitions selected:(NSString *)selectedId
{
  for (XPChipButton *chip in self.chipButtons) {
    [chip removeFromSuperview];
  }
  [self.chipButtons removeAllObjects];

  for (id definition in definitions) {
    if (![definition isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSDictionary *entry = (NSDictionary *)definition;
    NSString *title = entry[@"title"];
    NSString *identifier = entry[@"id"];
    XPChipButton *chip = [[XPChipButton alloc] initWithTitle:title];
    chip.tag = (NSInteger)self.chipButtons.count;
    chip.selected = [identifier isEqualToString:selectedId];
    [chip addTarget:self
                  action:@selector(chipTapped:)
        forControlEvents:UIControlEventTouchUpInside];
    [self.chipsScrollView addSubview:chip];
    [self.chipButtons addObject:chip];
  }
  [self layoutChips];
}

- (void)applyBrowseChips
{
  NSArray *definitions = @[
    @{ @"title" : @"Destacados", @"id" : XPColumnFeatured },
    @{ @"title" : @"Películas", @"id" : XPColumnMovies },
    @{ @"title" : @"Series", @"id" : XPColumnSeries },
    @{ @"title" : @"Anime", @"id" : XPColumnAnime },
    @{ @"title" : @"Infantil", @"id" : XPColumnKids },
    @{ @"title" : @"Gratis", @"id" : XPColumnFree }
  ];
  [self applyChips:definitions selected:self.activeColumnCode ?: XPColumnFeatured];
}

- (void)applySearchChips
{
  NSArray *definitions = @[
    @{ @"title" : @"Todo", @"id" : @"all" },
    @{ @"title" : @"Películas", @"id" : @"movie" },
    @{ @"title" : @"Series", @"id" : @"series" }
  ];
  [self applyChips:definitions selected:self.searchFilter ?: @"all"];
}

- (void)chipTapped:(XPChipButton *)sender
{
  NSUInteger index = (NSUInteger)sender.tag;
  if (index >= self.chipButtons.count) {
    return;
  }
  XPChipButton *chip = self.chipButtons[index];
  for (XPChipButton *other in self.chipButtons) {
    other.selected = (other == chip);
  }

  if (self.searching) {
    self.searchFilter = chip.chipTitle.length > 0 ? [self filterIdentifierForChip:chip] : @"all";
    [self applySearchChips];
    [self runSearch:self.searchText];
    return;
  }

  if (self.showsLiveChannels) {
    NSArray *categories = self.liveCategories;
    if (index < categories.count) {
      NSString *identifier = categories[index][@"id"];
      [self loadLiveChannelsForColumn:identifier];
    }
    return;
  }

  NSArray *definitions = @[
    XPColumnFeatured, XPColumnMovies, XPColumnSeries,
    XPColumnAnime, XPColumnKids, XPColumnFree
  ];
  if (index < definitions.count) {
    [self loadCatalogForColumn:definitions[index]];
  }
}

- (NSString *)filterIdentifierForChip:(XPChipButton *)chip
{
  if ([chip.chipTitle isEqualToString:@"Películas"]) {
    return @"movie";
  }
  if ([chip.chipTitle isEqualToString:@"Series"]) {
    return @"series";
  }
  return @"all";
}

- (void)loadCatalogForColumn:(NSString *)columnCode
{
  self.activeColumnCode = columnCode;
  self.currentPage = 1;
  self.loadingMore = NO;
  [self.sections removeAllObjects];
  [self.collectionView reloadData];
  [self.statusView showLoading];

  __weak XPCatalogViewController *weakSelf = self;
  [[XPPortalClient sharedClient] fetchSectionsForColumn:columnCode
                                                    page:1
                                              completion:^(NSArray *sections, NSError *error) {
    if (error != nil) {
      NSLog(@"[XuperPad] columna %@ error %@", columnCode, error.localizedDescription);
      [weakSelf.statusView showMessage:error.localizedDescription retry:YES];
      return;
    }
    NSLog(@"[XuperPad] columna %@ secciones %lu", columnCode, (unsigned long)sections.count);
    [weakSelf.statusView hideStatus];
    weakSelf.sections = [sections mutableCopy] ?: [NSMutableArray array];
    [weakSelf.collectionView reloadData];
  }];
}

- (void)loadLiveCategories
{
  [self.statusView showLoading];
  __weak XPCatalogViewController *weakSelf = self;
  [[XPPortalClient sharedClient] fetchLiveCategoriesWithCompletion:^(NSArray *categories, NSError *error) {
    if (error != nil) {
      [weakSelf.statusView showMessage:error.localizedDescription retry:YES];
      return;
    }
    [weakSelf.statusView hideStatus];
    weakSelf.liveCategories = categories ?: @[];
    NSMutableArray *definitions = [NSMutableArray array];
    for (id category in weakSelf.liveCategories) {
      if (![category isKindOfClass:[NSDictionary class]]) {
        continue;
      }
      [definitions addObject:@{ @"title" : ((NSDictionary *)category)[@"name"],
                                @"id" : ((NSDictionary *)category)[@"id"] }];
    }
    [weakSelf applyChips:definitions
                selected:definitions.firstObject[@"id"]];
    if (definitions.count > 0) {
      [weakSelf loadLiveChannelsForColumn:definitions.firstObject[@"id"]];
    } else {
      [weakSelf loadLiveChannelsForColumn:@"76182"];
    }
  }];
}

- (void)loadLiveChannelsForColumn:(NSString *)columnIdentifier
{
  self.activeColumnCode = columnIdentifier;
  self.currentPage = 1;
  self.loadingMore = NO;
  [self.sections removeAllObjects];
  [self.collectionView reloadData];
  [self.statusView showLoading];

  __weak XPCatalogViewController *weakSelf = self;
  [[XPPortalClient sharedClient] fetchLiveChannelsForColumn:columnIdentifier
                                                         page:1
                                                   completion:^(NSArray *channels, NSError *error) {
    if (error != nil) {
      [weakSelf.statusView showMessage:error.localizedDescription retry:YES];
      return;
    }
    [weakSelf.statusView hideStatus];
    if (channels.count > 0) {
      [weakSelf.sections addObject:@{ @"name" : @"Canales",
                                      @"items" : [channels mutableCopy] }];
    }
    [weakSelf.collectionView reloadData];
  }];
}

- (void)handleSearchText:(NSString *)text
{
  if (text.length == 0) {
    [self exitSearchMode];
    return;
  }
  self.searching = YES;
  self.searchText = text;
  [self applySearchChips];
  [self runSearch:text];
}

- (void)exitSearchMode
{
  self.searching = NO;
  self.searchText = @"";
  self.searchFilter = @"all";
  if (self.showsLiveChannels) {
    [self applyChips:@[] selected:nil];
    [self loadLiveCategories];
    return;
  }
  [self applyBrowseChips];
  [self loadCatalogForColumn:self.activeColumnCode ?: XPColumnFeatured];
}

- (void)runSearch:(NSString *)text
{
  if (text.length == 0) {
    return;
  }
  self.currentPage = 1;
  self.loadingMore = NO;
  [self.sections removeAllObjects];
  [self.collectionView reloadData];
  [self.statusView showLoading];

  __weak XPCatalogViewController *weakSelf = self;
  [[XPPortalClient sharedClient] searchTitles:text
                                          page:1
                                    completion:^(NSArray *titles, NSError *error) {
    if (error != nil) {
      NSLog(@"[XuperPad] busqueda %@ error %@", text, error.localizedDescription);
      [weakSelf.statusView showMessage:error.localizedDescription retry:YES];
      return;
    }
    NSLog(@"[XuperPad] busqueda %@ resultados %lu", text, (unsigned long)titles.count);
    [weakSelf.statusView hideStatus];
    NSArray *filtered = [weakSelf filterTitles:titles];
    if (filtered.count > 0) {
      [weakSelf.sections addObject:@{ @"name" : @"Resultados",
                                      @"items" : [filtered mutableCopy] }];
    }
    [weakSelf.collectionView reloadData];
  }];
}

- (NSArray *)filterTitles:(NSArray *)titles
{
  if (self.searchFilter.length == 0 || [self.searchFilter isEqualToString:@"all"]) {
    return titles ?: @[];
  }
  NSMutableArray *result = [NSMutableArray array];
  for (id title in titles) {
    if (![title isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    BOOL series = [((NSDictionary *)title)[@"series"] boolValue];
    if ([self.searchFilter isEqualToString:@"movie"] && series) {
      continue;
    }
    if ([self.searchFilter isEqualToString:@"series"] && !series) {
      continue;
    }
    [result addObject:title];
  }
  return result;
}

- (void)retryCurrentLoad
{
  if (self.searching) {
    [self runSearch:self.searchText];
    return;
  }
  if (self.showsLiveChannels) {
    [self loadLiveCategories];
    return;
  }
  [self loadCatalogForColumn:self.activeColumnCode ?: XPColumnFeatured];
}

- (void)loadNextPage
{
  if (self.loadingMore) {
    return;
  }
  self.loadingMore = YES;
  NSUInteger nextPage = self.currentPage + 1;

  __weak XPCatalogViewController *weakSelf = self;

  if (self.searching) {
    [[XPPortalClient sharedClient] searchTitles:self.searchText
                                           page:nextPage
                                     completion:^(NSArray *titles, NSError *error) {
      weakSelf.loadingMore = NO;
      if (error != nil || titles.count == 0) {
        return;
      }
      weakSelf.currentPage = nextPage;
      NSArray *filtered = [weakSelf filterTitles:titles];
      if (filtered.count == 0) {
        return;
      }
      if (weakSelf.sections.count == 0) {
        [weakSelf.sections addObject:@{ @"name" : @"Resultados",
                                         @"items" : [NSMutableArray array] }];
      }
      NSMutableArray *items = weakSelf.sections.firstObject[@"items"];
      [items addObjectsFromArray:filtered];
      [weakSelf.collectionView reloadData];
    }];
    return;
  }

  if (self.showsLiveChannels) {
    [[XPPortalClient sharedClient] fetchLiveChannelsForColumn:self.activeColumnCode
                                                          page:nextPage
                                                    completion:^(NSArray *channels, NSError *error) {
      weakSelf.loadingMore = NO;
      if (error != nil || channels.count == 0) {
        return;
      }
      weakSelf.currentPage = nextPage;
      if (weakSelf.sections.count == 0) {
        [weakSelf.sections addObject:@{ @"name" : @"Canales",
                                         @"items" : [NSMutableArray array] }];
      }
      NSMutableArray *items = weakSelf.sections.firstObject[@"items"];
      [items addObjectsFromArray:channels];
      [weakSelf.collectionView reloadData];
    }];
    return;
  }

  [[XPPortalClient sharedClient] fetchSectionsForColumn:self.activeColumnCode
                                                    page:nextPage
                                              completion:^(NSArray *sections, NSError *error) {
    weakSelf.loadingMore = NO;
    if (error != nil || sections.count == 0) {
      return;
    }
    weakSelf.currentPage = nextPage;
    [weakSelf.sections addObjectsFromArray:sections];
    [weakSelf.collectionView reloadData];
  }];
}

#pragma mark - XPDrawnCollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(XPDrawnCollectionView *)collectionView
{
  return (NSInteger)self.sections.count;
}

- (NSInteger)collectionView:(XPDrawnCollectionView *)collectionView
     numberOfItemsInSection:(NSInteger)section
{
  if (section < 0 || (NSUInteger)section >= self.sections.count) {
    return 0;
  }
  NSArray *items = self.sections[(NSUInteger)section][@"items"];
  if (![items isKindOfClass:[NSArray class]]) {
    return 0;
  }
  return (NSInteger)items.count;
}

- (XPDrawnCollectionViewCell *)collectionView:(XPDrawnCollectionView *)collectionView
                        cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
  XPCardCell *cell = (XPCardCell *)[collectionView
      dequeueReusableCellWithReuseIdentifier:XPCellIdentifier
                                forIndexPath:indexPath];
  NSArray *items = self.sections[(NSUInteger)indexPath.section][@"items"];
  if ((NSUInteger)indexPath.item < items.count) {
    [cell applyTitle:items[(NSUInteger)indexPath.item]];
  }
  if ((NSInteger)items.count - indexPath.item <= 4) {
    [self loadNextPage];
  }
  return cell;
}

#pragma mark - XPDrawnCollectionViewDelegate

- (void)collectionView:(XPDrawnCollectionView *)collectionView
  didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
  if ((NSUInteger)indexPath.section >= self.sections.count) {
    return;
  }
  NSArray *items = self.sections[(NSUInteger)indexPath.section][@"items"];
  if ((NSUInteger)indexPath.item >= items.count) {
    return;
  }
  NSDictionary *item = items[(NSUInteger)indexPath.item];

  if (self.showsLiveChannels) {
    [self openLiveChannel:item];
    return;
  }

  XPDetailViewController *detail =
      [[XPDetailViewController alloc] initWithTitle:item];
  [[self xpNavigationController] pushViewController:detail animated:YES];
}

- (UIView *)collectionView:(XPDrawnCollectionView *)collectionView
    viewForSupplementaryElementOfKind:(NSString *)kind
                          atIndexPath:(NSIndexPath *)indexPath
{
  XPSectionHeaderView *header = (XPSectionHeaderView *)[collectionView
      dequeueReusableSupplementaryViewOfKind:kind
                         withReuseIdentifier:XPSectionIdentifier
                                forIndexPath:indexPath];
  if (indexPath.section < 0 || (NSUInteger)indexPath.section >= self.sections.count) {
    return header;
  }
  NSArray *items = self.sections[(NSUInteger)indexPath.section][@"items"];
  NSString *name = self.sections[(NSUInteger)indexPath.section][@"name"];
  [header applyTitle:name count:[items isKindOfClass:[NSArray class]] ? items.count : 0];
  return header;
}

- (void)openLiveChannel:(NSDictionary *)item
{
  NSString *channelCode = item[@"id"];
  NSString *channelName = item[@"name"];
  [self.statusView showLoading];

  __weak XPCatalogViewController *weakSelf = self;
  [XPStreamResolver resolveLiveForChannel:channelCode
                                     title:channelName
                                completion:^(NSDictionary *stream, NSError *error) {
    if (stream == nil) {
      [weakSelf.statusView showMessage:error.localizedDescription ?: @"No se pudo abrir el canal"
                                  retry:YES];
      return;
    }
    [weakSelf.statusView hideStatus];
    XPPlayerViewController *player = [XPPlayerViewController playerWithStream:stream];
    [[weakSelf xpNavigationController] pushViewController:player animated:YES];
  }];
}

@end
