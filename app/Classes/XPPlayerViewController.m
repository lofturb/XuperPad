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
#import "XPOptionsPanel.h"
#import "XPSubtitleOverlay.h"
#import "XPPlayerControls.h"
#import "XPTheme.h"
#import "XPDrawnLabel.h"
#import "XPDrawnNavigationController.h"

#import <math.h>

static const NSTimeInterval XPPlayerStartTimeout = 45.0;
static const NSTimeInterval XPPlayerControlsTimeout = 3.5;
static const NSTimeInterval XPPlayerRefreshInterval = 0.5;
static const NSTimeInterval XPPlayerSubtitleInterval = 0.2;
static const NSTimeInterval XPPlayerToastTimeout = 2.4;
static const CGFloat XPPlayerChapterBarHeight = 84.0f;
static const CGFloat XPPlayerOptionsHeight = 226.0f;
static const double XPPlayerChapterRestartLimit = 8.0;
static const NSTimeInterval XPPlayerNextChapterDelay = 4.0;

@interface XPPlayerViewController () <XPDecoderDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, strong) XPGLView *glView;
@property (nonatomic, strong) XPDecoder *decoder;
@property (nonatomic, strong) XPPlayerControls *controls;
@property (nonatomic, strong) XPChapterBar *chapterBar;
@property (nonatomic, strong) XPOptionsPanel *optionsPanel;
@property (nonatomic, strong) XPSubtitleOverlay *subtitleOverlay;
@property (nonatomic, strong) XPStatusView *statusView;
@property (nonatomic, strong) XPDrawnLabel *toastLabel;
@property (nonatomic, assign) NSUInteger currentIndex;
@property (nonatomic, strong) NSMutableArray *addressQueue;
@property (nonatomic, assign) BOOL observing;
@property (nonatomic, strong) NSTimer *startTimeout;
@property (nonatomic, strong) NSTimer *refreshTimer;
@property (nonatomic, strong) NSTimer *subtitleTimer;
@property (nonatomic, strong) NSTimer *toastTimer;
@property (nonatomic, strong) NSTimer *endTimer;
@property (nonatomic, assign) BOOL userPaused;
@property (nonatomic, assign) BOOL playbackFinished;
@property (nonatomic, assign) BOOL chapterBarVisible;
@property (nonatomic, assign) BOOL optionsPanelVisible;
@property (nonatomic, assign) float playbackRate;
@property (nonatomic, strong) NSDate *lastInteraction;
@property (nonatomic, copy) NSString *contentId;
@property (nonatomic, copy) NSArray *streamTracks;
@property (nonatomic, assign) NSInteger selectedTrackIndex;
@property (nonatomic, copy) NSArray *displayQualityTracks;
@property (nonatomic, assign) double pendingResumeTime;
@property (nonatomic, assign) BOOL hasPendingResume;
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
  controller.contentId = stream[@"contentId"];
  NSArray *tracks = stream[@"tracks"];
  controller.streamTracks = [tracks isKindOfClass:[NSArray class]] ? tracks : @[];
  controller.selectedTrackIndex = [stream[@"selectedTrackIndex"] integerValue];
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

  self.subtitleOverlay = [[XPSubtitleOverlay alloc] initWithFrame:self.view.bounds];
  [self.view addSubview:self.subtitleOverlay];

  self.optionsPanel = [[XPOptionsPanel alloc] initWithFrame:CGRectZero];
  self.optionsPanel.alpha = 0.0f;
  self.optionsPanel.hidden = YES;
  self.playbackRate = 1.0f;
  self.optionsPanel.playbackRate = 1.0f;
  self.optionsPanel.audioSelectionHandler = ^(NSInteger index) {
    [weakSelf audioTrackSelectedAtIndex:index];
  };
  self.optionsPanel.subtitleSelectionHandler = ^(NSInteger index) {
    [weakSelf subtitleTrackSelectedAtIndex:index];
  };
  self.optionsPanel.qualitySelectionHandler = ^(NSInteger index) {
    [weakSelf qualitySelectedAtIndex:index];
  };
  self.optionsPanel.rateSelectionHandler = ^(float rate) {
    [weakSelf playbackRateSelected:rate];
  };
  self.optionsPanel.closeHandler = ^{
    [weakSelf setOptionsPanelVisible:NO];
  };
  [self.view addSubview:self.optionsPanel];

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
  self.controls.chaptersHandler = ^{
    [weakSelf toggleChapterBar];
  };
  self.controls.moreHandler = ^{
    [weakSelf toggleOptionsPanel];
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

  [self refreshQualityOptions];
  [self startPlayback];
  [self showControls];

  self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:XPPlayerRefreshInterval
                                                        target:self
                                                      selector:@selector(refreshInterface)
                                                      userInfo:nil
                                                       repeats:YES];

  self.subtitleTimer = [NSTimer scheduledTimerWithTimeInterval:XPPlayerSubtitleInterval
                                                         target:self
                                                       selector:@selector(refreshSubtitle)
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
  self.subtitleOverlay.frame = self.view.bounds;

  CGFloat barBottom = height - 92.0f;
  CGFloat barTop = barBottom - XPPlayerChapterBarHeight;
  if (barTop < 56.0f) {
    barTop = 56.0f;
    barBottom = barTop + XPPlayerChapterBarHeight;
  }
  self.chapterBar.frame = CGRectMake(0.0f, barTop, width, XPPlayerChapterBarHeight);

  CGFloat panelBottom = height - 96.0f;
  CGFloat panelTop = panelBottom - XPPlayerOptionsHeight;
  if (panelTop < 40.0f) {
    panelTop = 40.0f;
    panelBottom = MIN(height - 96.0f, panelTop + XPPlayerOptionsHeight);
  }
  self.optionsPanel.frame = CGRectMake(0.0f, panelTop, width, panelBottom - panelTop);

  self.toastLabel.frame = CGRectMake((width - 280.0f) / 2.0f,
                                     barTop - 44.0f,
                                     280.0f,
                                     30.0f);
}

- (void)viewWillDisappear:(BOOL)animated
{
  [super viewWillDisappear:animated];
  [self stopPlayback];
}

- (void)startPlayback
{
  [self stopPlayback];
  self.playbackFinished = NO;
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
  decoder.playbackRate = self.playbackRate;
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
  [self.endTimer invalidate];
  self.endTimer = nil;

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
  [self.subtitleOverlay clearCue];
  self.optionsPanel.audioTracks = @[];
  self.optionsPanel.subtitleTracks = @[];
  self.optionsPanel.selectedAudioIndex = -1;
  self.optionsPanel.selectedSubtitleIndex = -1;
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
      if (self.hasPendingResume) {
        CMTime resumeTime = CMTimeMakeWithSeconds(self.pendingResumeTime, 600);
        [self.player seekToTime:resumeTime];
        self.hasPendingResume = NO;
      }
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
  self.hasPendingResume = NO;
  [self startPlayback];
}

- (void)closeTapped:(id)sender
{
  [[self xpNavigationController] popViewControllerAnimated:YES];
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
  if (self.decoder == nil && self.player == nil && self.playbackFinished) {
    self.playbackFinished = NO;
    self.currentIndex = 0;
    [self startPlayback];
    return;
  }
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
  [self cancelAutomaticChapter];
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
  [self cancelAutomaticChapter];
  NSInteger index = self.currentChapterIndex + 1;
  if (index >= (NSInteger)self.chapters.count) {
    [self showTransientMessage:@"Es el último capítulo disponible"];
    return;
  }
  [self openChapterAtIndex:index];
}

- (void)chapterSelectedAtIndex:(NSInteger)index
{
  [self cancelAutomaticChapter];
  if (index == self.currentChapterIndex) {
    [self seekToFraction:0.0f];
    return;
  }
  [self openChapterAtIndex:index];
}

- (void)cancelAutomaticChapter
{
  [self.endTimer invalidate];
  self.endTimer = nil;
}

- (void)openChapterAtIndex:(NSInteger)index
{
  if (index < 0 || index >= (NSInteger)self.chapters.count) {
    return;
  }
  [self cancelAutomaticChapter];
  self.playbackFinished = NO;
  self.hasPendingResume = NO;
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
  id contentId = stream[@"contentId"];
  if ([contentId isKindOfClass:[NSString class]] && [(NSString *)contentId length] > 0) {
    self.contentId = contentId;
  }
  NSArray *tracks = stream[@"tracks"];
  self.streamTracks = [tracks isKindOfClass:[NSArray class]] ? tracks : @[];
  self.selectedTrackIndex = [stream[@"selectedTrackIndex"] integerValue];
  [self refreshQualityOptions];
}

- (void)refreshQualityOptions
{
  NSMutableArray *display = [NSMutableArray array];
  NSArray *tracks = self.streamTracks;
  BOOL hasCapped = NO;
  for (id item in tracks) {
    if (![item isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSInteger height = [((NSDictionary *)item)[@"height"] integerValue];
    if (height > 0 && height <= 720) {
      hasCapped = YES;
      break;
    }
  }
  for (id item in tracks) {
    if (![item isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSDictionary *track = (NSDictionary *)item;
    NSInteger height = [track[@"height"] integerValue];
    if (hasCapped && height > 720) {
      continue;
    }
    NSString *title = track[@"title"];
    if (![title isKindOfClass:[NSString class]] || title.length == 0) {
      title = @"Auto";
    }
    [display addObject:@{ @"index" : track[@"index"] ?: @0, @"title" : title }];
  }
  self.displayQualityTracks = display;

  NSMutableArray *titles = [NSMutableArray array];
  NSInteger selected = -1;
  for (NSUInteger position = 0; position < display.count; position++) {
    NSDictionary *entry = display[position];
    [titles addObject:entry[@"title"]];
    if ([entry[@"index"] integerValue] == self.selectedTrackIndex) {
      selected = (NSInteger)position;
    }
  }
  self.optionsPanel.qualityTitles = titles;
  self.optionsPanel.selectedQualityIndex = selected;
}

- (void)qualitySelectedAtIndex:(NSInteger)index
{
  if (index < 0 || index >= (NSInteger)self.displayQualityTracks.count) {
    return;
  }
  NSDictionary *entry = self.displayQualityTracks[(NSUInteger)index];
  [self switchToTrackIndex:[entry[@"index"] integerValue]];
}

- (void)switchToTrackIndex:(NSInteger)trackIndex
{
  if (trackIndex == self.selectedTrackIndex) {
    [self showTransientMessage:@"Esa calidad ya esta activa"];
    return;
  }
  if (self.contentId.length == 0) {
    [self showTransientMessage:@"No se puede cambiar la calidad aqui"];
    return;
  }
  NSInteger previousIndex = self.selectedTrackIndex;
  double resume = [self elapsedSeconds];
  BOOL wasPlaying = !self.userPaused;
  self.selectedTrackIndex = trackIndex;
  self.pendingResumeTime = resume;
  self.hasPendingResume = resume > 1.0;
  [self setOptionsPanelVisible:NO];
  [self.statusView showLoading];
  [self showTransientMessage:@"Cambiando la calidad"];

  NSString *title = self.seriesName.length > 0 ? self.seriesName : self.titleText;
  __weak XPPlayerViewController *weakSelf = self;
  [XPStreamResolver resolveOnDemandForTitle:self.contentId
                                   seriesId:self.seriesId
                                      title:title
                                 trackIndex:trackIndex
                                 completion:^(NSDictionary *stream, NSError *error) {
    XPPlayerViewController *strongSelf = weakSelf;
    if (strongSelf == nil) {
      return;
    }
    if (stream == nil) {
      strongSelf.hasPendingResume = NO;
      strongSelf.selectedTrackIndex = previousIndex;
      [strongSelf refreshQualityOptions];
      [strongSelf.statusView showMessage:error.localizedDescription ?: @"No se pudo cambiar la calidad"
                                   retry:YES];
      return;
    }
    [strongSelf applyStream:stream];
    [strongSelf startPlayback];
    if (!wasPlaying) {
      strongSelf.userPaused = YES;
      if (strongSelf.decoder != nil) {
        strongSelf.decoder.paused = YES;
      } else if (strongSelf.player != nil) {
        [strongSelf.player pause];
      }
    }
  }];
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

  if (!self.controls.hidden && !self.chapterBarVisible && !self.optionsPanelVisible
      && self.lastInteraction != nil) {
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
  if (self.chapterBarVisible || self.optionsPanelVisible) {
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
    [self setOptionsPanelVisible:NO];
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
  [self setOptionsPanelVisible:NO];
  [self setChapterBarVisible:!self.chapterBarVisible];
  [self showControls];
}

- (void)toggleOptionsPanel
{
  [self setChapterBarVisible:NO];
  [self setOptionsPanelVisible:!self.optionsPanelVisible];
  [self showControls];
}

- (void)setOptionsPanelVisible:(BOOL)visible
{
  _optionsPanelVisible = visible;
  if (visible) {
    self.optionsPanel.hidden = NO;
    [self.view bringSubviewToFront:self.optionsPanel];
    [self.view bringSubviewToFront:self.controls];
    [UIView animateWithDuration:0.2 animations:^{
      self.optionsPanel.alpha = 1.0f;
    }];
    return;
  }
  [UIView animateWithDuration:0.2 animations:^{
    self.optionsPanel.alpha = 0.0f;
  } completion:^(BOOL finished) {
    if (finished) {
      self.optionsPanel.hidden = YES;
    }
  }];
}

- (void)setChapterBarVisible:(BOOL)visible
{
  _chapterBarVisible = visible;
  if (visible) {
    self.chapterBar.hidden = NO;
    [self.view bringSubviewToFront:self.chapterBar];
    [self.view bringSubviewToFront:self.controls];
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

- (void)audioTrackSelectedAtIndex:(NSInteger)index
{
  if (self.decoder == nil) {
    [self showTransientMessage:@"Esta reproducción no permite cambiar el idioma del audio"];
    return;
  }
  if (![self.decoder selectAudioTrack:index]) {
    [self showTransientMessage:@"No se pudo cambiar el idioma del audio"];
    return;
  }
  self.optionsPanel.selectedAudioIndex = index;
  [self showTransientMessage:@"Cambiando el idioma del audio"];
}

- (void)subtitleTrackSelectedAtIndex:(NSInteger)index
{
  if (self.decoder == nil) {
    [self showTransientMessage:@"Esta reproducción no permite cambiar los subtítulos"];
    return;
  }
  if (![self.decoder selectSubtitleTrack:index]) {
    [self showTransientMessage:@"No se pudieron cambiar los subtítulos"];
    return;
  }
  self.optionsPanel.selectedSubtitleIndex = index;
  if (index < 0) {
    [self.subtitleOverlay clearCue];
    [self showTransientMessage:@"Subtítulos desactivados"];
  } else {
    [self showTransientMessage:@"Subtítulos activados"];
  }
}

- (void)playbackRateSelected:(float)rate
{
  self.playbackRate = rate;
  self.optionsPanel.playbackRate = rate;
  if (self.decoder != nil) {
    self.decoder.playbackRate = rate;
  } else if (self.player != nil) {
    self.player.rate = rate;
  }
  [self showTransientMessage:[NSString stringWithFormat:@"Velocidad %.2gx", rate]];
}

- (void)refreshSubtitle
{
  if (self.decoder == nil) {
    return;
  }
  XPSubtitleCue *cue = self.decoder.activeSubtitle;
  if (cue == nil) {
    [self.subtitleOverlay clearCue];
    return;
  }
  [self.subtitleOverlay showCue:cue];
}

- (void)showTransientMessage:(NSString *)message
{
  if (self.toastLabel == nil) {
    XPDrawnLabel *label = [[XPDrawnLabel alloc] initWithFrame:CGRectZero];
    label.font = XPFontCaption(11.5f);
    label.textColor = XPColorTextPrimary();
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 1;
    label.textInsets = UIEdgeInsetsMake(0.0f, 14.0f, 0.0f, 14.0f);
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
      [view isDescendantOfView:self.optionsPanel] ||
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
  if (self.hasPendingResume) {
    [self.decoder seekToTime:self.pendingResumeTime];
    self.hasPendingResume = NO;
  }
}

- (void)decoder:(XPDecoder *)decoder didProduceVideoFrame:(XPVideoFrameData *)frame
{
  if (decoder != self.decoder) {
    return;
  }
  [self.glView displayFrame:frame];
}

- (void)decoder:(XPDecoder *)decoder didUpdateAudioTracks:(NSArray *)tracks selectedIndex:(NSInteger)selectedIndex
{
  if (decoder != self.decoder) {
    return;
  }
  self.optionsPanel.audioTracks = tracks ?: @[];
  self.optionsPanel.selectedAudioIndex = selectedIndex;
  self.optionsPanel.informationText = decoder.informationText;
}

- (void)decoder:(XPDecoder *)decoder didUpdateSubtitleTracks:(NSArray *)tracks selectedIndex:(NSInteger)selectedIndex
{
  if (decoder != self.decoder) {
    return;
  }
  self.optionsPanel.subtitleTracks = tracks ?: @[];
  self.optionsPanel.selectedSubtitleIndex = selectedIndex;
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
  [self handlePlaybackFinished:message];
}

- (void)handlePlaybackFinished:(NSString *)message
{
  self.playbackFinished = YES;
  self.userPaused = YES;
  self.controls.playing = NO;
  [self.statusView showMessage:message ?: @"El contenido ha terminado." retry:NO];
  NSInteger nextIndex = self.currentChapterIndex + 1;
  if (self.chapters.count > 0 && nextIndex < (NSInteger)self.chapters.count) {
    NSString *nextTitle = [self chapterTitleAtIndex:nextIndex];
    [self showTransientMessage:[NSString stringWithFormat:@"Siguiente capítulo en %ld s: %@",
                                 (long)XPPlayerNextChapterDelay, nextTitle]];
    [self showControls];
    [self.endTimer invalidate];
    self.endTimer = [NSTimer scheduledTimerWithTimeInterval:XPPlayerNextChapterDelay
                                                      target:self
                                                    selector:@selector(advanceToNextChapter)
                                                    userInfo:nil
                                                     repeats:NO];
    return;
  }
  [self showTransientMessage:message ?: @"El contenido ha terminado"];
  [self showControls];
}

- (void)advanceToNextChapter
{
  self.endTimer = nil;
  NSInteger nextIndex = self.currentChapterIndex + 1;
  if (nextIndex >= (NSInteger)self.chapters.count) {
    return;
  }
  [self openChapterAtIndex:nextIndex];
}

- (void)dealloc
{
  [self.refreshTimer invalidate];
  [self.subtitleTimer invalidate];
  [self.toastTimer invalidate];
  [self.startTimeout invalidate];
  [self.endTimer invalidate];
  [self stopPlayback];
}

@end
