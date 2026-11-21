//
//  XPPlayerViewController.m
//

#import "XPPlayerViewController.h"

#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>

#import "XPDecoder.h"
#import "XPGLView.h"
#import "XPStatusView.h"
#import "XPBackControl.h"
#import "XPTheme.h"

static const NSTimeInterval XPPlayerStartTimeout = 45.0;

@interface XPPlayerViewController () <XPDecoderDelegate>
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, strong) XPGLView *glView;
@property (nonatomic, strong) XPDecoder *decoder;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) XPStatusView *statusView;
@property (nonatomic, strong) XPBackControl *backControl;
@property (nonatomic, assign) NSUInteger currentIndex;
@property (nonatomic, strong) NSMutableArray *addressQueue;
@property (nonatomic, assign) BOOL observing;
@property (nonatomic, strong) NSTimer *startTimeout;
@end

@implementation XPPlayerViewController

+ (instancetype)playerWithStream:(NSDictionary *)stream
{
  XPPlayerViewController *controller = [[XPPlayerViewController alloc] init];
  controller.titleText = stream[@"title"];
  controller.streamAddress = stream[@"url"];
  controller.streamHeaders = stream[@"headers"];
  controller.streamType = stream[@"mime"];
  controller.streamCodec = stream[@"codec"];
  controller.streamFormat = stream[@"format"];
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

  self.glView = [[XPGLView alloc] initWithFrame:self.view.bounds];
  self.glView.hidden = YES;
  [self.view addSubview:self.glView];

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

  self.addressQueue = [self buildAddressQueue];

  [self startPlayback];
}

- (NSMutableArray *)buildAddressQueue
{
  NSMutableArray *queue = [NSMutableArray array];
  if (self.streamAddress.length > 0) {
    [queue addObject:@{ @"url" : self.streamAddress,
                        @"headers" : self.streamHeaders ?: @{},
                        @"codec" : self.streamCodec ?: @"",
                        @"format" : self.streamFormat ?: @"" }];
  }
  for (id item in self.backupAddresses) {
    if ([item isKindOfClass:[NSDictionary class]]) {
      NSDictionary *entry = (NSDictionary *)item;
      NSString *address = entry[@"url"];
      if ([address isKindOfClass:[NSString class]] && address.length > 0) {
        [queue addObject:@{ @"url" : address,
                            @"headers" : entry[@"headers"] ?: self.streamHeaders ?: @{},
                            @"codec" : entry[@"codec"] ?: self.streamCodec ?: @"",
                            @"format" : entry[@"format"] ?: self.streamFormat ?: @"" }];
      }
    } else if ([item isKindOfClass:[NSString class]] && [item length] > 0) {
      [queue addObject:@{ @"url" : item,
                          @"headers" : self.streamHeaders ?: @{},
                          @"codec" : self.streamCodec ?: @"",
                          @"format" : self.streamFormat ?: @"" }];
    }
  }
  return queue;
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
  self.glView.frame = self.view.bounds;
  self.statusView.frame = self.view.bounds;
  self.backControl.frame = CGRectMake(12.0f, 12.0f, 34.0f, 34.0f);
  self.titleLabel.frame = CGRectMake(56.0f, 14.0f, MAX(40.0f, width - 68.0f), 30.0f);
  self.titleLabel.layer.cornerRadius = 8.0f;
  self.titleLabel.layer.masksToBounds = YES;
}

- (void)viewWillDisappear:(BOOL)animated
{
  [super viewWillDisappear:animated];
  if (self.isMovingFromParentViewController) {
    [self stopPlayback];
  }
}

- (void)startPlayback
{
  [self stopPlayback];
  if (self.currentIndex >= self.addressQueue.count) {
    [self.statusView showMessage:@"No se pudo reproducir el contenido." retry:YES];
    return;
  }

  NSDictionary *entry = self.addressQueue[self.currentIndex];
  NSString *address = entry[@"url"];
  if (![address isKindOfClass:[NSString class]] || address.length == 0) {
    [self currentIndexDidFail];
    return;
  }
  NSDictionary *headers = entry[@"headers"];
  if (![headers isKindOfClass:[NSDictionary class]]) {
    headers = @{};
  }

  [self.statusView showLoading];

  BOOL software = [self needsSoftwareDecoderForEntry:entry];
  NSLog(@"[XuperPad] reproductor: intento %lu de %lu %@ decodificador %@",
        (unsigned long)(self.currentIndex + 1),
        (unsigned long)self.addressQueue.count,
        address,
        software ? @"software" : @"sistema");

  if (software) {
    [self startSoftwarePlaybackWithAddress:address headers:headers];
  } else {
    [self startSystemPlaybackWithAddress:address headers:headers];
  }

  [self scheduleStartTimeout];
}

- (BOOL)needsSoftwareDecoderForEntry:(NSDictionary *)entry
{
  NSString *codec = @"";
  id rawCodec = entry[@"codec"];
  if ([rawCodec isKindOfClass:[NSString class]]) {
    codec = [(NSString *)rawCodec lowercaseString];
  }
  if ([codec isEqualToString:@"hevc"] || [codec isEqualToString:@"h265"]) {
    return YES;
  }
  NSString *format = @"";
  id rawFormat = entry[@"format"];
  if ([rawFormat isKindOfClass:[NSString class]]) {
    format = [(NSString *)rawFormat lowercaseString];
  }
  if ([format isEqualToString:@"ts"] || [format isEqualToString:@"mpegts"]) {
    return YES;
  }
  NSString *mime = [self.streamType isKindOfClass:[NSString class]]
                     ? [self.streamType lowercaseString]
                     : @"";
  if ([mime isEqualToString:@"video/mp2t"]) {
    return YES;
  }
  return NO;
}

- (void)startSystemPlaybackWithAddress:(NSString *)address headers:(NSDictionary *)headers
{
  NSURL *url = [NSURL URLWithString:address];
  if (url == nil) {
    [self currentIndexDidFail];
    return;
  }

  NSDictionary *options = nil;
  if (headers.count > 0) {
    options = @{ @"AVURLAssetHTTPHeaderFieldsKey" : headers };
  }
  AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:options];
  AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];
  AVPlayer *player = [AVPlayer playerWithPlayerItem:item];

  self.player = player;
  self.playerLayer.player = player;
  self.playerLayer.hidden = NO;
  self.glView.hidden = YES;

  [player addObserver:self
           forKeyPath:@"status"
              options:NSKeyValueObservingOptionNew
              context:NULL];
  self.observing = YES;
  [player play];
}

- (void)startSoftwarePlaybackWithAddress:(NSString *)address headers:(NSDictionary *)headers
{
  XPDecoder *decoder = [[XPDecoder alloc] init];
  decoder.delegate = self;
  CGSize target = self.view.bounds.size;
  if (target.width > 1.0 && target.height > 1.0) {
    decoder.presentationSize = target;
  }
  self.decoder = decoder;

  self.playerLayer.hidden = YES;
  self.glView.hidden = NO;
  [self.glView clearFrame];

  if (![decoder startWithAddress:address headers:headers]) {
    [self currentIndexDidFail];
  }
}

- (void)scheduleStartTimeout
{
  [self.startTimeout invalidate];
  self.startTimeout = [NSTimer scheduledTimerWithTimeInterval:XPPlayerStartTimeout
                                                      target:self
                                                    selector:@selector(startTimeoutFired:)
                                                    userInfo:nil
                                                     repeats:NO];
}

- (void)startTimeoutFired:(NSTimer *)timer
{
  self.startTimeout = nil;
  [self currentIndexDidFail];
}

- (void)stopPlayback
{
  [self.startTimeout invalidate];
  self.startTimeout = nil;

  if (self.decoder != nil) {
    [self.decoder stop];
    self.decoder.delegate = nil;
    self.decoder = nil;
  }

  if (self.player != nil) {
    if (self.observing) {
      @try {
        [self.player removeObserver:self forKeyPath:@"status"];
      } @catch (NSException *exception) {
      }
      self.observing = NO;
    }
    [self.player pause];
    self.player = nil;
  }
  self.playerLayer.player = nil;
  [self.glView clearFrame];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                       ofObject:(id)object
                         change:(NSDictionary *)change
                        context:(void *)context
{
  if (![keyPath isEqualToString:@"status"] || object != self.player) {
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    return;
  }
  AVPlayer *player = (AVPlayer *)object;
  if (player.status == AVPlayerStatusReadyToPlay) {
    [self.startTimeout invalidate];
    self.startTimeout = nil;
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
  [self stopPlayback];
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

- (void)decoder:(XPDecoder *)decoder didOpenVideoWithWidth:(int)width height:(int)height
{
  if (decoder != self.decoder) {
    return;
  }
  [self.startTimeout invalidate];
  self.startTimeout = nil;
  [self.statusView hideStatus];
}

- (void)decoder:(XPDecoder *)decoder didProduceVideoFrame:(XPVideoFrameData *)frame
{
  if (decoder != self.decoder) {
    return;
  }
  [self.glView displayFrame:frame];
}

- (void)decoder:(XPDecoder *)decoder didFailWithMessage:(NSString *)message
{
  if (decoder != self.decoder) {
    return;
  }
  NSLog(@"[XuperPad] decodificador: %@", message);
  [self currentIndexDidFail];
}

- (void)decoder:(XPDecoder *)decoder didFinishWithMessage:(NSString *)message
{
  if (decoder != self.decoder) {
    return;
  }
  [self stopPlayback];
  [self.statusView showMessage:message ?: @"El contenido ha terminado." retry:NO];
}

- (void)dealloc
{
  [self stopPlayback];
}

@end
