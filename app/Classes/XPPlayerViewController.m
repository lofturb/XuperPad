//
//  XPPlayerViewController.m
//

#import "XPPlayerViewController.h"

#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>

#import "XPDecoder.h"
#import "XPGLView.h"
#import "XPStatusView.h"
#import "XPStreamResolver.h"
#import "XPChapterBar.h"
#import "XPPlayerControls.h"
#import "XPTheme.h"

#import <math.h>

static const NSTimeInterval XPPlayerStartTimeout = 45.0;
static const NSTimeInterval XPPlayerControlsTimeout = 3.5;
static const NSTimeInterval XPPlayerRefreshInterval = 0.5;
static const NSTimeInterval XPPlayerToastTimeout = 2.4;
static const CGFloat XPPlayerChapterBarHeight = 84.0f;
static const double XPPlayerChapterRestartLimit = 8.0;

@interface XPPlayerViewController () <XPDecoderDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, strong) XPGLView *glView;
@property (nonatomic, strong) XPDecoder *decoder;
@property (nonatomic, strong) XPPlayerControls *controls;
@property (nonatomic, strong) XPChapterBar *chapterBar;
@property (nonatomic, strong) XPStatusView *statusView;
@property (nonatomic, strong) UILabel *toastLabel;
@property (nonatomic, assign) NSUInteger currentIndex;
@property (nonatomic, strong) NSMutableArray *addressQueue;
@property (nonatomic, assign) BOOL observing;
@property (nonatomic, strong) NSTimer *startTimeout;
@property (nonatomic, strong) NSTimer *refreshTimer;
@property (nonatomic, strong) NSTimer *toastTimer;
@property (nonatomic, assign) BOOL userPaused;
@property (nonatomic, assign) BOOL chapterBarVisible;
@property (nonatomic, strong) NSDate *lastInteraction;
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

  self.statusView = [[XPStatusView alloc] initWithFrame:self.view.bounds];
  self.statusView.backgroundColor = [UIColor clearColor];
  __weak XPPlayerViewController *weakSelf = self;
  self.statusView.retryHandler = ^{
    [weakSelf retryPlayback];
  };
  [self.view addSubview:self.statusView];

  self.chapterBar = [[XPChapterBar alloc] initWithFrame:CGRectZero];
  self.chapterBar.alpha = 0.0f;
  self.chapterBar.hidden = YES;
  __weak XPPlayerViewController *weakChapterSelf = self;
  self.chapterBar.previousHandler = ^{
    [weakChapterSelf previousChapterTapped];
  };
  self.chapterBar.nextHandler = ^{
    [weakChapterSelf nextChapterTapped];
  };
  self.chapterBar.selectionHandler = ^(NSInteger index) {
    [weakChapterSelf chapterSelectedAtIndex:index];
  };
  [self.view addSubview:self.chapterBar];

  self.controls = [[XPPlayerControls alloc] initWithFrame:self.view.bounds];
  self.controls.liveStream = self.chapters.count == 0;
  self.controls.closeHandler = ^{
    [weakSelf closeTapped:nil];
  };
  self.controls.playPauseHandler = ^{
    [weakSelf togglePlayPause];
  };
  self.controls.previousChapterHandler = ^{
    [weakSelf previousChapterTapped];
  };
  self.controls.nextChapterHandler = ^{
    [weakSelf nextChapterTapped];
  };
  self.controls.moreHandler = ^{
    [weakSelf toggleChapterBar];
  };
  self.controls.seekHandler = ^(float fraction) {
    [weakSelf seekToFraction:fraction];
  };
  [self.view addSubview:self.controls];

  UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                         action:@selector(toggleControls)];
  tap.delegate = self;
  [self.view addGestureRecognizer:tap];

  self.addressQueue = [self buildAddressQueue];
  self.chapterBar.chapters = self.chapters;
  self.chapterBar.currentIndex = self.currentChapterIndex;
  [self updateChapterLabels];

  [self startPlayback];
  [self showControls];

  self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:XPPlayerRefreshInterval
                                                        target:self
                                                      selector:@selector(refreshInterface)
                                                      userInfo:nil
                                                       repeats:YES];
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
  self.controls.frame = self.view.bounds;

  CGFloat barBottom = height - 92.0f;
  CGFloat barTop = barBottom - XPPlayerChapterBarHeight;
  if (barTop < 56.0f) {
    barTop = 56.0f;
    barBottom = barTop + XPPlayerChapterBarHeight;
  }
  self.chapterBar.frame = CGRectMake(0.0f, barTop, width, XPPlayerChapterBarHeight);
  self.toastLabel.frame = CGRectMake((width - 280.0f) / 2.0f,
                                     barTop - 44.0f,
                                     280.0f,
                                     30.0f);
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

  self.userPaused = NO;
  self.controls.playing = YES;
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

- (double)elapsedSeconds
{
  if (self.decoder != nil) {
    return self.decoder.currentTime;
  }
  if (self.player != nil) {
    NSTimeInterval value = CMTimeGetSeconds(self.player.currentTime);
    if (isnan(value)) {
      return 0.0;
    }
    return value;
  }
  return 0.0;
}

- (double)totalSeconds
{
  if (self.decoder != nil) {
    return self.decoder.duration;
  }
  if (self.player != nil && self.player.currentItem != nil) {
    NSTimeInterval value = CMTimeGetSeconds(self.player.currentItem.duration);
    if (isnan(value)) {
      return 0.0;
    }
    return value;
  }
  return 0.0;
}

- (void)togglePlayPause
{
  if (self.decoder != nil) {
    self.userPaused = !self.userPaused;
    self.decoder.paused = self.userPaused;
  } else if (self.player != nil) {
    if (self.player.rate > 0.0f) {
      [self.player pause];
      self.userPaused = YES;
    } else {
      [self.player play];
      self.userPaused = NO;
    }
  }
  self.controls.playing = !self.userPaused;
  [self showControls];
}

- (void)seekToFraction:(float)fraction
{
  double total = [self totalSeconds];
  if (total <= 0.0) {
    [self showTransientMessage:@"La búsqueda no está disponible en este contenido"];
    [self showControls];
    return;
  }
  double target = total * (double)MAX(0.0f, MIN(1.0f, fraction));
  if (self.decoder != nil) {
    if (![self.decoder seekToTime:target]) {
      [self showTransientMessage:@"No se pudo buscar en este contenido"];
    }
  } else if (self.player != nil) {
    CMTime time = CMTimeMakeWithSeconds(target, 600);
    [self.player seekToTime:time];
  }
  [self showControls];
}

- (void)previousChapterTapped
{
  if (self.chapters.count == 0) {
    return;
  }
  if ([self elapsedSeconds] > XPPlayerChapterRestartLimit) {
    [self seekToFraction:0.0f];
    [self showTransientMessage:@"Repitiendo el capítulo actual"];
    return;
  }
  NSInteger index = self.currentChapterIndex - 1;
  if (index < 0) {
    index = 0;
    [self seekToFraction:0.0f];
    return;
  }
  [self openChapterAtIndex:index];
}

- (void)nextChapterTapped
{
  if (self.chapters.count == 0) {
    return;
  }
  NSInteger index = self.currentChapterIndex + 1;
  if (index >= (NSInteger)self.chapters.count) {
    [self showTransientMessage:@"Es el último capítulo disponible"];
    return;
  }
  [self openChapterAtIndex:index];
}

- (void)chapterSelectedAtIndex:(NSInteger)index
{
  if (index == self.currentChapterIndex) {
    [self seekToFraction:0.0f];
    return;
  }
  [self openChapterAtIndex:index];
}

- (void)openChapterAtIndex:(NSInteger)index
{
  if (index < 0 || index >= (NSInteger)self.chapters.count) {
    return;
  }
  id item = self.chapters[index];
  if (![item isKindOfClass:[NSDictionary class]]) {
    return;
  }
  NSDictionary *chapter = (NSDictionary *)item;
  id rawId = chapter[@"id"];
  if (![rawId isKindOfClass:[NSString class]] || [rawId length] == 0) {
    [self showTransientMessage:@"El capítulo no tiene una dirección reproducible"];
    return;
  }
  NSString *episodeId = (NSString *)rawId;
  NSString *title = self.seriesName.length > 0 ? self.seriesName : self.titleText;

  [self.statusView showLoading];
  __weak XPPlayerViewController *weakSelf = self;
  [XPStreamResolver resolveOnDemandForTitle:episodeId
                                   seriesId:self.seriesId
                                      title:title
                                 completion:^(NSDictionary *stream, NSError *error) {
    XPPlayerViewController *strongSelf = weakSelf;
    if (strongSelf == nil) {
      return;
    }
    if (stream == nil) {
      [strongSelf.statusView showMessage:error.localizedDescription ?: @"No se pudo abrir el capítulo"
                                    retry:YES];
      return;
    }
    strongSelf.currentChapterIndex = index;
    [strongSelf applyStream:stream];
    [strongSelf updateChapterLabels];
    strongSelf.chapterBar.currentIndex = index;
    [strongSelf startPlayback];
  }];
}

- (void)applyStream:(NSDictionary *)stream
{
  self.streamAddress = stream[@"url"];
  self.streamHeaders = stream[@"headers"];
  self.streamType = stream[@"mime"];
  self.streamCodec = stream[@"codec"];
  self.streamFormat = stream[@"format"];
  NSArray *backups = stream[@"backupUrls"];
  self.backupAddresses = [backups isKindOfClass:[NSArray class]] ? backups : @[];
  self.addressQueue = [self buildAddressQueue];
  self.currentIndex = 0;
}

- (NSString *)chapterTitleAtIndex:(NSInteger)index
{
  if (index < 0 || index >= (NSInteger)self.chapters.count) {
    return @"";
  }
  id item = self.chapters[index];
  if (![item isKindOfClass:[NSDictionary class]]) {
    return @"";
  }
  NSDictionary *chapter = (NSDictionary *)item;
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

- (void)updateChapterLabels
{
  NSString *title = self.seriesName.length > 0 ? self.seriesName : self.titleText;
  self.controls.titleText = title ?: @"";
  self.controls.subtitleText = [self chapterTitleAtIndex:self.currentChapterIndex];
}

- (void)refreshInterface
{
  double elapsed = [self elapsedSeconds];
  double total = [self totalSeconds];
  self.controls.elapsedTime = elapsed;
  self.controls.duration = total;
  float progress = 0.0f;
  if (total > 0.0) {
    progress = (float)(elapsed / total);
  }
  self.controls.progress = MAX(0.0f, MIN(1.0f, progress));
  self.controls.playing = !self.userPaused;

  if (!self.controls.hidden && !self.chapterBarVisible && self.lastInteraction != nil) {
    NSTimeInterval idle = [[NSDate date] timeIntervalSinceDate:self.lastInteraction];
    if (idle > XPPlayerControlsTimeout) {
      [self hideControls];
    }
  }
}

- (void)showControls
{
  self.lastInteraction = [NSDate date];
  if (self.controls.hidden) {
    self.controls.hidden = NO;
    self.controls.alpha = 0.0f;
  }
  [UIView animateWithDuration:0.18 animations:^{
    self.controls.alpha = 1.0f;
  }];
}

- (void)hideControls
{
  if (self.chapterBarVisible) {
    return;
  }
  [UIView animateWithDuration:0.25 animations:^{
    self.controls.alpha = 0.0f;
  } completion:^(BOOL finished) {
    if (finished) {
      self.controls.hidden = YES;
    }
  }];
}

- (void)toggleControls
{
  if (!self.controls.hidden) {
    [self setChapterBarVisible:NO];
    [UIView animateWithDuration:0.25 animations:^{
      self.controls.alpha = 0.0f;
    } completion:^(BOOL finished) {
      if (finished) {
        self.controls.hidden = YES;
      }
    }];
    return;
  }
  [self showControls];
}

- (void)toggleChapterBar
{
  if (self.chapters.count == 0) {
    [self showTransientMessage:@"Este contenido no tiene capítulos disponibles"];
    [self showControls];
    return;
  }
  [self setChapterBarVisible:!self.chapterBarVisible];
  [self showControls];
}

- (void)setChapterBarVisible:(BOOL)visible
{
  _chapterBarVisible = visible;
  if (visible) {
    self.chapterBar.hidden = NO;
    [UIView animateWithDuration:0.2 animations:^{
      self.chapterBar.alpha = 1.0f;
    }];
    return;
  }
  [UIView animateWithDuration:0.2 animations:^{
    self.chapterBar.alpha = 0.0f;
  } completion:^(BOOL finished) {
    if (finished) {
      self.chapterBar.hidden = YES;
    }
  }];
}

- (void)showTransientMessage:(NSString *)message
{
  if (self.toastLabel == nil) {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.font = XPFontCaption(11.5f);
    label.textColor = XPColorTextPrimary();
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 1;
    label.backgroundColor = [XPColorSurfaceAlt() colorWithAlphaComponent:0.95f];
    label.layer.cornerRadius = 15.0f;
    label.layer.masksToBounds = YES;
    label.alpha = 0.0f;
    [self.view addSubview:label];
    self.toastLabel = label;
    [self.view setNeedsLayout];
  }
  self.toastLabel.text = message ?: @"";
  [self.view bringSubviewToFront:self.toastLabel];
  [UIView animateWithDuration:0.2 animations:^{
    self.toastLabel.alpha = 1.0f;
  }];
  [self.toastTimer invalidate];
  self.toastTimer = [NSTimer scheduledTimerWithTimeInterval:XPPlayerToastTimeout
                                                      target:self
                                                    selector:@selector(hideToast:)
                                                    userInfo:nil
                                                     repeats:NO];
}

- (void)hideToast:(NSTimer *)timer
{
  self.toastTimer = nil;
  [UIView animateWithDuration:0.25 animations:^{
    self.toastLabel.alpha = 0.0f;
  }];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
        shouldReceiveTouch:(UITouch *)touch
{
  UIView *view = touch.view;
  if (view == nil) {
    return YES;
  }
  if ([view isDescendantOfView:self.controls] ||
      [view isDescendantOfView:self.chapterBar] ||
      [view isDescendantOfView:self.statusView]) {
    return NO;
  }
  return YES;
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
  [self.refreshTimer invalidate];
  [self.toastTimer invalidate];
  [self.startTimeout invalidate];
  [self stopPlayback];
}

@end
