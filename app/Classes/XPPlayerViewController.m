//
//  XPPlayerViewController.m
//

#import "XPPlayerViewController.h"

#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>

#import "XPStatusView.h"
#import "XPBackControl.h"
#import "XPTheme.h"

@interface XPPlayerViewController ()
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) XPStatusView *statusView;
@property (nonatomic, strong) XPBackControl *backControl;
@property (nonatomic, assign) NSUInteger currentIndex;
@property (nonatomic, strong) NSMutableArray *addressQueue;
@property (nonatomic, assign) BOOL observing;
@end

@implementation XPPlayerViewController

+ (instancetype)playerWithStream:(NSDictionary *)stream
{
  XPPlayerViewController *controller = [[XPPlayerViewController alloc] init];
  controller.titleText = stream[@"title"];
  controller.streamAddress = stream[@"url"];
  controller.streamHeaders = stream[@"headers"];
  controller.streamType = stream[@"mime"];
  NSArray *backups = stream[@"backupUrls"];
  controller.backupAddresses = [backups isKindOfClass:[NSArray class]] ? backups : @[];
  return controller;
}

- (void)viewDidLoad
{
  [super viewDidLoad];
  self.view.backgroundColor = [UIColor blackColor];
  self.edgesForExtendedLayout = UIRectEdgeAll;

  self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:nil];
  self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
  [self.view.layer addSublayer:self.playerLayer];

  self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
  self.titleLabel.font = XPFontMedium(13.0f);
  self.titleLabel.textColor = XPColorTextPrimary();
  self.titleLabel.backgroundColor = [XPColorSurface() colorWithAlphaComponent:0.72f];
  self.titleLabel.textAlignment = NSTextAlignmentCenter;
  self.titleLabel.text = self.titleText ?: @"";
  self.titleLabel.numberOfLines = 1;
  self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  [self.view addSubview:self.titleLabel];

  self.backControl = [[XPBackControl alloc] initWithFrame:CGRectZero];
  [self.backControl addTarget:self
                        action:@selector(closeTapped:)
              forControlEvents:UIControlEventTouchUpInside];
  [self.view addSubview:self.backControl];

  self.statusView = [[XPStatusView alloc] initWithFrame:self.view.bounds];
  self.statusView.backgroundColor = [UIColor clearColor];
  __weak XPPlayerViewController *weakSelf = self;
  self.statusView.retryHandler = ^{
    [weakSelf retryPlayback];
  };
  [self.view addSubview:self.statusView];

  NSMutableArray *queue = [NSMutableArray array];
  if (self.streamAddress.length > 0) {
    [queue addObject:@{ @"url" : self.streamAddress,
                        @"headers" : self.streamHeaders ?: @{} }];
  }
  for (id item in self.backupAddresses) {
    if ([item isKindOfClass:[NSDictionary class]]) {
      NSDictionary *entry = (NSDictionary *)item;
      NSString *address = entry[@"url"];
      if ([address isKindOfClass:[NSString class]] && address.length > 0) {
        [queue addObject:@{ @"url" : address,
                            @"headers" : entry[@"headers"] ?: self.streamHeaders ?: @{} }];
      }
    } else if ([item isKindOfClass:[NSString class]] && [item length] > 0) {
      [queue addObject:@{ @"url" : item,
                          @"headers" : self.streamHeaders ?: @{} }];
    }
  }
  self.addressQueue = queue;

  [self startPlayback];
}

- (BOOL)prefersStatusBarHidden
{
  return YES;
}

- (void)viewDidLayoutSubviews
{
  [super viewDidLayoutSubviews];
  CGFloat width = CGRectGetWidth(self.view.bounds);
  CGFloat height = CGRectGetHeight(self.view.bounds);

  self.playerLayer.frame = self.view.bounds;
  self.statusView.frame = self.view.bounds;
  self.backControl.frame = CGRectMake(12.0f, 12.0f, 34.0f, 34.0f);
  self.titleLabel.frame = CGRectMake(56.0f, 14.0f, MAX(40.0f, width - 68.0f), 30.0f);
  self.titleLabel.layer.cornerRadius = 8.0f;
  self.titleLabel.layer.masksToBounds = YES;
}

- (void)startPlayback
{
  if (self.currentIndex >= self.addressQueue.count) {
    [self.statusView showMessage:@"No se pudo reproducir el contenido." retry:YES];
    return;
  }

  NSDictionary *entry = self.addressQueue[self.currentIndex];
  NSString *address = entry[@"url"];
  NSURL *url = [NSURL URLWithString:address];
  if (url == nil) {
    [self currentIndexDidFail];
    return;
  }

  AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
  NSDictionary *headers = entry[@"headers"];
  NSArray *headerValues = headers.allValues;
  if (headerValues.count > 0) {
    NSMutableDictionary *options = [NSMutableDictionary dictionary];
    [options setObject:headerValues forKey:@"AVURLAssetHTTPHeaderFieldsKey"];
    asset = [AVURLAsset URLAssetWithURL:url options:options];
  }

  [self.statusView showLoading];

  AVPlayer *player = [AVPlayer playerWithPlayerItem:[AVPlayerItem playerItemWithAsset:asset]];
  self.player = player;
  self.playerLayer.player = player;
  [player addObserver:self
           forKeyPath:@"status"
              options:NSKeyValueObservingOptionNew
              context:nil];
  self.observing = YES;
  [player play];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                       ofObject:(id)object
                         change:(NSDictionary *)change
                        context:(void *)context
{
  if (![keyPath isEqualToString:@"status"]) {
    return;
  }
  AVPlayer *player = (AVPlayer *)object;
  if (player.status == AVPlayerStatusReadyToPlay) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self.statusView hideStatus];
    });
  } else if (player.status == AVPlayerStatusFailed) {
    [self currentIndexDidFail];
  }
}

- (void)currentIndexDidFail
{
  self.currentIndex++;
  if (self.currentIndex < self.addressQueue.count) {
    [self startPlayback];
    return;
  }
  [self.statusView showMessage:@"No se pudo reproducir el contenido." retry:YES];
}

- (void)retryPlayback
{
  self.currentIndex = 0;
  [self startPlayback];
}

- (void)closeTapped:(id)sender
{
  [self.navigationController popViewControllerAnimated:YES];
}

- (void)dealloc
{
  if (self.player != nil && self.observing) {
    @try {
      [self.player removeObserver:self forKeyPath:@"status"];
    } @catch (NSException *exception) {
    }
    self.observing = NO;
  }
  [self.player pause];
  self.player = nil;
}

@end
