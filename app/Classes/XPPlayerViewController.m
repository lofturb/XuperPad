//
//  XPPlayerViewController.m
//

#import "XPPlayerViewController.h"

#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>

@interface XPPlayerViewController ()
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, assign) NSUInteger currentIndex;
@property (nonatomic, strong) NSMutableArray *addressQueue;
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
  self.title = self.titleText;

  self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:nil];
  self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
  [self.view.layer addSublayer:self.playerLayer];

  self.spinner = [[UIActivityIndicatorView alloc]
      initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
  self.spinner.center = self.view.center;
  self.spinner.autoresizingMask =
      UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin |
      UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
  [self.view addSubview:self.spinner];

  self.messageLabel = [[UILabel alloc] initWithFrame:CGRectZero];
  self.messageLabel.textAlignment = NSTextAlignmentCenter;
  self.messageLabel.textColor = [UIColor whiteColor];
  self.messageLabel.font = [UIFont systemFontOfSize:16];
  self.messageLabel.numberOfLines = 0;
  self.messageLabel.backgroundColor = [UIColor clearColor];
  [self.view addSubview:self.messageLabel];

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

- (void)viewDidLayoutSubviews
{
  [super viewDidLayoutSubviews];
  self.playerLayer.frame = self.view.bounds;
  self.messageLabel.frame = CGRectInset(self.view.bounds, 20, 20);
}

- (void)startPlayback
{
  if (self.currentIndex >= self.addressQueue.count) {
    [self showMessage:@"No se pudo reproducir el contenido."];
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

  self.spinner.hidden = NO;
  [self.spinner startAnimating];
  self.messageLabel.hidden = YES;

  self.player = [AVPlayer playerWithPlayerItem:[AVPlayerItem playerItemWithAsset:asset]];
  self.playerLayer.player = self.player;
  [self.player play];

  __weak XPPlayerViewController *weakSelf = self;
  [self.player addObserver:self
                forKeyPath:@"status"
                   options:NSKeyValueObservingOptionNew
                   context:nil];
  weakSelf.player = self.player;
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
      [self.spinner stopAnimating];
      self.spinner.hidden = YES;
      self.messageLabel.hidden = YES;
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
  [self showMessage:@"No se pudo reproducir el contenido."];
}

- (void)showMessage:(NSString *)text
{
  [self.spinner stopAnimating];
  self.spinner.hidden = YES;
  self.messageLabel.text = text;
  self.messageLabel.hidden = NO;
}

- (void)dealloc
{
  if (self.player != nil) {
    @try {
      [self.player removeObserver:self forKeyPath:@"status"];
    } @catch (NSException *exception) {
    }
    [self.player pause];
  }
}

@end
