//
//  XPCatalogViewController.m
//

#import "XPCatalogViewController.h"
#import "XPConstants.h"
#import "XPPortalClient.h"
#import "XPTitleCell.h"
#import "XPDetailViewController.h"
#import "XPStreamResolver.h"
#import "XPPlayerViewController.h"

static NSString *const XPCellIdentifier = @"XPTitleCell";

@interface XPCatalogViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISegmentedControl *columnControl;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSMutableArray *items;
@property (nonatomic, assign) NSUInteger currentPage;
@property (nonatomic, assign) BOOL loadingMore;
@property (nonatomic, assign) BOOL searchMode;
@property (nonatomic, copy) NSString *searchText;
@property (nonatomic, copy) NSString *activeColumnCode;
@property (nonatomic, copy) NSArray *liveCategories;
@end

@implementation XPCatalogViewController

- (void)viewDidLoad
{
  [super viewDidLoad];
  self.title = self.screenTitle;
  self.view.backgroundColor = [UIColor whiteColor];
  self.items = [NSMutableArray array];
  self.currentPage = 1;

  [self buildInterface];

  if (self.showsLiveChannels) {
    [self loadLiveCategories];
  } else {
    [self loadCatalogForColumn:XPColumnFeatured];
  }
}

- (void)buildInterface
{
  self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds
                                                  style:UITableViewStylePlain];
  self.tableView.dataSource = self;
  self.tableView.delegate = self;
  self.tableView.rowHeight = 100;
  [self.tableView registerClass:[XPTitleCell class]
         forCellReuseIdentifier:XPCellIdentifier];
  self.tableView.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [self.view addSubview:self.tableView];

  if (!self.showsLiveChannels) {
    NSArray *names = @[ @"Destacados", @"Peliculas", @"Series", @"Anime",
                        @"Infantil", @"Gratis" ];
    NSArray *codes = @[ XPColumnFeatured, XPColumnMovies, XPColumnSeries,
                        XPColumnAnime, XPColumnKids, XPColumnFree ];
    self.columnControl = [[UISegmentedControl alloc] initWithItems:names];
    self.columnControl.selectedSegmentIndex = 0;
    self.columnControl.frame = CGRectMake(0, 0, self.view.bounds.size.width, 36);
    self.columnControl.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.columnControl addTarget:self
                            action:@selector(columnChanged:)
                  forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = self.columnControl;

    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectZero];
    self.searchBar.delegate = self;
    self.searchBar.placeholder = @"Buscar en el catalogo";
    self.searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.searchBar.frame = CGRectMake(0, 0, self.view.bounds.size.width, 52);
    [self.view addSubview:self.searchBar];
  }
}

- (void)viewDidLayoutSubviews
{
  [super viewDidLayoutSubviews];
  if (self.searchBar != nil) {
    self.searchBar.frame = CGRectMake(0, 0, self.view.bounds.size.width, 52);
    self.tableView.frame = CGRectMake(0, 52, self.view.bounds.size.width,
                                      self.view.bounds.size.height - 52);
  }
}

- (void)columnChanged:(UISegmentedControl *)sender
{
  NSArray *codes = @[ XPColumnFeatured, XPColumnMovies, XPColumnSeries,
                      XPColumnAnime, XPColumnKids, XPColumnFree ];
  if (sender.selectedSegmentIndex >= codes.count) {
    return;
  }
  [self loadCatalogForColumn:codes[sender.selectedSegmentIndex]];
}

- (void)loadCatalogForColumn:(NSString *)columnCode
{
  self.activeColumnCode = columnCode;
  self.currentPage = 1;
  [self.items removeAllObjects];
  [self.tableView reloadData];

  __weak XPCatalogViewController *weakSelf = self;
  [[XPPortalClient sharedClient] fetchTitlesForColumn:columnCode
                                                   page:1
                                             completion:^(NSArray *titles, NSError *error) {
    [weakSelf applyLoadedTitles:titles error:error];
  }];
}

- (void)loadLiveCategories
{
  __weak XPCatalogViewController *weakSelf = self;
  [[XPPortalClient sharedClient] fetchLiveCategoriesWithCompletion:^(NSArray *categories, NSError *error) {
    weakSelf.liveCategories = categories;
    if (categories.count > 0) {
      weakSelf.activeColumnCode = categories.firstObject[@"id"];
      [weakSelf loadLiveChannelsForColumn:weakSelf.activeColumnCode];
    } else {
      [weakSelf loadLiveChannelsForColumn:@"76182"];
    }
  }];
}

- (void)loadLiveChannelsForColumn:(NSString *)columnIdentifier
{
  self.activeColumnCode = columnIdentifier;
  self.currentPage = 1;
  [self.items removeAllObjects];
  [self.tableView reloadData];

  __weak XPCatalogViewController *weakSelf = self;
  [[XPPortalClient sharedClient] fetchLiveChannelsForColumn:columnIdentifier
                                                         page:1
                                                   completion:^(NSArray *channels, NSError *error) {
    [weakSelf applyLoadedTitles:channels error:error];
  }];
}

- (void)applyLoadedTitles:(NSArray *)titles error:(NSError *)error
{
  if (error != nil) {
    [self showFailure:error];
    return;
  }
  [self.items addObjectsFromArray:titles];
  [self.tableView reloadData];
}

- (void)loadNextPage
{
  if (self.loadingMore) {
    return;
  }
  self.loadingMore = YES;
  NSUInteger nextPage = self.currentPage + 1;

  __weak XPCatalogViewController *weakSelf = self;
  void (^apply)(NSArray *, NSError *) = ^(NSArray *titles, NSError *error) {
    weakSelf.loadingMore = NO;
    if (error != nil) {
      return;
    }
    weakSelf.currentPage = nextPage;
    [weakSelf.items addObjectsFromArray:titles];
    [weakSelf.tableView reloadData];
  };

  if (self.searchMode) {
    [[XPPortalClient sharedClient] searchTitles:self.searchText
                                           page:nextPage
                                     completion:apply];
  } else if (self.showsLiveChannels) {
    [[XPPortalClient sharedClient] fetchLiveChannelsForColumn:self.activeColumnCode
                                                         page:nextPage
                                                   completion:apply];
  } else {
    [[XPPortalClient sharedClient] fetchTitlesForColumn:self.activeColumnCode
                                                   page:nextPage
                                             completion:apply];
  }
}

- (void)showFailure:(NSError *)error
{
  UIAlertController *alert =
      [UIAlertController alertControllerWithTitle:@"Sin conexion"
                                          message:error.localizedDescription
                                   preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"Aceptar"
                                            style:UIAlertActionStyleDefault
                                          handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
  return self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
  XPTitleCell *cell = [tableView dequeueReusableCellWithIdentifier:XPCellIdentifier
                                                        forIndexPath:indexPath];
  [cell applyTitle:self.items[indexPath.row]];
  return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
  [tableView deselectRowAtIndexPath:indexPath animated:YES];
  if (indexPath.row >= self.items.count) {
    return;
  }
  NSDictionary *item = self.items[indexPath.row];

  if (self.showsLiveChannels) {
    [self openLiveChannel:item];
    return;
  }

  XPDetailViewController *detail =
      [[XPDetailViewController alloc] initWithTitle:item];
  [self.navigationController pushViewController:detail animated:YES];
}

- (void)tableView:(UITableView *)tableView
  willDisplayCell:(UITableViewCell *)cell
forRowAtIndexPath:(NSIndexPath *)indexPath
{
  if (indexPath.row >= (NSInteger)self.items.count - 5) {
    [self loadNextPage];
  }
}

- (void)openLiveChannel:(NSDictionary *)item
{
  NSString *channelCode = item[@"id"];
  NSString *channelName = item[@"name"];
  UIAlertController *alert =
      [UIAlertController alertControllerWithTitle:channelName
                                          message:@"Preparando el canal..."
                                   preferredStyle:UIAlertControllerStyleAlert];
  [self presentViewController:alert animated:YES completion:nil];

  [XPStreamResolver resolveLiveForChannel:channelCode
                                     title:channelName
                                completion:^(NSDictionary *stream, NSError *error) {
    [alert dismissViewControllerAnimated:YES completion:nil];
    if (stream == nil) {
      [self showFailure:error];
      return;
    }
    XPPlayerViewController *player = [XPPlayerViewController playerWithStream:stream];
    [self.navigationController pushViewController:player animated:YES];
  }];
}

#pragma mark - UISearchBarDelegate

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar
{
  NSString *text = searchBar.text;
  [searchBar resignFirstResponder];
  if (text.length == 0) {
    return;
  }
  self.searchMode = YES;
  self.searchText = text;
  self.currentPage = 1;
  [self.items removeAllObjects];
  [self.tableView reloadData];

  __weak XPCatalogViewController *weakSelf = self;
  [[XPPortalClient sharedClient] searchTitles:text
                                         page:1
                                   completion:^(NSArray *titles, NSError *error) {
    [weakSelf applyLoadedTitles:titles error:error];
  }];
}

@end
