//
//  XPDetailViewController.m
//

#import "XPDetailViewController.h"
#import "XPPortalClient.h"
#import "XPStreamResolver.h"
#import "XPPlayerViewController.h"

static NSString *const XPEpisodeCellIdentifier = @"XPEpisodeCell";

@interface XPDetailViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) NSDictionary *catalogTitle;
@property (nonatomic, strong) NSDictionary *detailInfo;
@property (nonatomic, strong) NSMutableArray *episodes;
@property (nonatomic, strong) UIImageView *posterView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *summaryLabel;
@property (nonatomic, strong) UITableView *episodeTable;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation XPDetailViewController

- (instancetype)initWithTitle:(NSDictionary *)title
{
  self = [super initWithNibName:nil bundle:nil];
  if (self) {
    _catalogTitle = title ?: @{};
    _episodes = [NSMutableArray array];
  }
  return self;
}

- (void)viewDidLoad
{
  [super viewDidLoad];
  self.title = self.catalogTitle[@"name"];
  self.view.backgroundColor = [UIColor whiteColor];

  [self buildInterface];
  [self loadDetail];
}

- (void)buildInterface
{
  self.posterView = [[UIImageView alloc] initWithFrame:CGRectZero];
  self.posterView.contentMode = UIViewContentModeScaleAspectFill;
  self.posterView.clipsToBounds = YES;
  self.posterView.backgroundColor = [UIColor colorWithWhite:0.16 alpha:1.0];
  [self.view addSubview:self.posterView];

  self.nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
  self.nameLabel.font = [UIFont boldSystemFontOfSize:20];
  self.nameLabel.numberOfLines = 2;
  self.nameLabel.text = self.catalogTitle[@"name"];
  [self.view addSubview:self.nameLabel];

  self.summaryLabel = [[UILabel alloc] initWithFrame:CGRectZero];
  self.summaryLabel.font = [UIFont systemFontOfSize:14];
  self.summaryLabel.numberOfLines = 0;
  self.summaryLabel.text = self.catalogTitle[@"summary"];
  [self.view addSubview:self.summaryLabel];

  self.spinner = [[UIActivityIndicatorView alloc]
      initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
  [self.spinner startAnimating];
  [self.view addSubview:self.spinner];

  self.episodeTable = [[UITableView alloc] initWithFrame:CGRectZero
                                                    style:UITableViewStylePlain];
  self.episodeTable.dataSource = self;
  self.episodeTable.delegate = self;
  self.episodeTable.rowHeight = 48;
  [self.episodeTable registerClass:[UITableViewCell class]
          forCellReuseIdentifier:XPEpisodeCellIdentifier];
  [self.view addSubview:self.episodeTable];
}

- (void)viewDidLayoutSubviews
{
  [super viewDidLayoutSubviews];
  CGFloat margin = 16;
  CGFloat width = self.view.bounds.size.width;
  CGFloat posterWidth = 110;
  CGFloat posterHeight = 154;

  self.posterView.frame = CGRectMake(margin, margin + 8, posterWidth, posterHeight);
  self.nameLabel.frame = CGRectMake(margin + posterWidth + margin,
                                    margin + 8,
                                    width - margin * 2 - posterWidth - margin,
                                    44);
  self.summaryLabel.frame = CGRectMake(margin + posterWidth + margin,
                                       margin + 56,
                                       width - margin * 2 - posterWidth - margin,
                                       100);
  self.spinner.center = CGPointMake(width / 2, margin + posterHeight / 2);
  CGFloat tableOrigin = margin + posterHeight + margin + 24;
  self.episodeTable.frame = CGRectMake(0, tableOrigin, width,
                                       self.view.bounds.size.height - tableOrigin);
}

- (void)loadDetail
{
  NSString *contentId = self.catalogTitle[@"id"];
  BOOL isSeries = [self.catalogTitle[@"series"] boolValue];
  __weak XPDetailViewController *weakSelf = self;
  [[XPPortalClient sharedClient] fetchDetailForTitle:contentId
                                              isSeries:isSeries
                                            completion:^(NSDictionary *detail, NSError *error) {
    [weakSelf.spinner stopAnimating];
    if (detail == nil) {
      [weakSelf showFailure:error];
      return;
    }
    weakSelf.detailInfo = detail;
    weakSelf.episodes = [detail[@"episodes"] mutableCopy] ?: [NSMutableArray array];
    NSString *name = detail[@"name"];
    if (name.length > 0) {
      weakSelf.nameLabel.text = name;
      weakSelf.title = name;
    }
    NSString *summary = detail[@"summary"];
    if (summary.length > 0) {
      weakSelf.summaryLabel.text = summary;
    }
    [weakSelf.episodeTable reloadData];
  }];
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
  return self.episodes.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
  UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:XPEpisodeCellIdentifier
                                                          forIndexPath:indexPath];
  NSDictionary *episode = self.episodes[indexPath.row];
  cell.textLabel.text = episode[@"name"];
  cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
  return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
  [tableView deselectRowAtIndexPath:indexPath animated:YES];
  if (indexPath.row >= self.episodes.count) {
    return;
  }
  NSDictionary *episode = self.episodes[indexPath.row];
  NSString *episodeId = episode[@"id"];
  NSString *seriesId = self.catalogTitle[@"id"];
  NSString *titleName = self.catalogTitle[@"name"];

  UIAlertController *alert =
      [UIAlertController alertControllerWithTitle:titleName
                                          message:@"Preparando la reproduccion..."
                                   preferredStyle:UIAlertControllerStyleAlert];
  [self presentViewController:alert animated:YES completion:nil];

  [XPStreamResolver resolveOnDemandForTitle:episodeId
                                    seriesId:seriesId
                                       title:titleName
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

@end
