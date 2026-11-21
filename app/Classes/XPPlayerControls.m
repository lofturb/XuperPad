#import "XPPlayerControls.h"

#import "XPBackControl.h"
#import "XPTheme.h"

#import <math.h>

@interface XPPlayerIconButton : UIControl
@property (nonatomic, assign) XPPlayerControlIcon icon;
@property (nonatomic, assign) BOOL emphasized;
@end

@implementation XPPlayerIconButton

- (instancetype)initWithFrame:(CGRect)frame
{
  self = [super initWithFrame:frame];
  if (self) {
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;
  }
  return self;
}

- (void)setIcon:(XPPlayerControlIcon)icon
{
  _icon = icon;
  [self setNeedsDisplay];
}

- (void)setEmphasized:(BOOL)emphasized
{
  _emphasized = emphasized;
  [self setNeedsDisplay];
}

- (void)setHighlighted:(BOOL)highlighted
{
  [super setHighlighted:highlighted];
  [UIView animateWithDuration:0.12 animations:^{
    self.alpha = highlighted ? 0.72f : 1.0f;
  }];
}

- (void)drawRect:(CGRect)rect
{
  CGContextRef context = UIGraphicsGetCurrentContext();
  if (context == NULL) {
    return;
  }
  CGFloat side = MIN(CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds));
  CGRect area = CGRectMake((CGRectGetWidth(self.bounds) - side) / 2.0f,
                            (CGRectGetHeight(self.bounds) - side) / 2.0f,
                            side,
                            side);
  if (area.size.width <= 4.0f || area.size.height <= 4.0f) {
    return;
  }

  if (self.emphasized) {
    XPDrawHorizontalGradient(context,
                             CGRectInset(area, 1.0f, 1.0f),
                             XPColorAccent(),
                             XPColorAccentAlt());
  } else {
    [[XPColorSurfaceAlt() colorWithAlphaComponent:0.78f] setFill];
    [XPRoundedPath(area, side / 2.0f) fill];
  }

  UIColor *ink = self.emphasized ? [UIColor whiteColor] : XPColorTextPrimary();
  [ink setFill];
  [ink setStroke];

  CGFloat midX = CGRectGetMidX(area);
  CGFloat midY = CGRectGetMidY(area);
  CGFloat unit = side / 24.0f;

  switch (self.icon) {
    case XPPlayerControlIconPlay: {
      UIBezierPath *triangle = [UIBezierPath bezierPath];
      [triangle moveToPoint:CGPointMake(midX - unit * 3.5f, midY - unit * 6.0f)];
      [triangle addLineToPoint:CGPointMake(midX + unit * 6.0f, midY)];
      [triangle addLineToPoint:CGPointMake(midX - unit * 3.5f, midY + unit * 6.0f)];
      [triangle closePath];
      [triangle fill];
      break;
    }
    case XPPlayerControlIconPause: {
      CGRect leftBar = CGRectMake(midX - unit * 5.0f, midY - unit * 6.0f,
                                   unit * 3.4f, unit * 12.0f);
      CGRect rightBar = CGRectMake(midX + unit * 1.6f, midY - unit * 6.0f,
                                    unit * 3.4f, unit * 12.0f);
      [XPRoundedPath(leftBar, unit * 1.1f) fill];
      [XPRoundedPath(rightBar, unit * 1.1f) fill];
      break;
    }
    case XPPlayerControlIconPreviousChapter: {
      UIBezierPath *triangle = [UIBezierPath bezierPath];
      [triangle moveToPoint:CGPointMake(midX + unit * 5.0f, midY - unit * 6.0f)];
      [triangle addLineToPoint:CGPointMake(midX - unit * 3.5f, midY)];
      [triangle addLineToPoint:CGPointMake(midX + unit * 5.0f, midY + unit * 6.0f)];
      [triangle closePath];
      [triangle fill];
      CGRect bar = CGRectMake(midX - unit * 6.5f, midY - unit * 6.0f,
                               unit * 2.0f, unit * 12.0f);
      [XPRoundedPath(bar, unit * 0.9f) fill];
      break;
    }
    case XPPlayerControlIconNextChapter: {
      UIBezierPath *triangle = [UIBezierPath bezierPath];
      [triangle moveToPoint:CGPointMake(midX - unit * 5.0f, midY - unit * 6.0f)];
      [triangle addLineToPoint:CGPointMake(midX + unit * 3.5f, midY)];
      [triangle addLineToPoint:CGPointMake(midX - unit * 5.0f, midY + unit * 6.0f)];
      [triangle closePath];
      [triangle fill];
      CGRect bar = CGRectMake(midX + unit * 4.5f, midY - unit * 6.0f,
                               unit * 2.0f, unit * 12.0f);
      [XPRoundedPath(bar, unit * 0.9f) fill];
      break;
    }
    case XPPlayerControlIconMore: {
      for (int index = 0; index < 3; index++) {
        CGFloat centerX = midX + (CGFloat)(index - 1) * unit * 5.0f;
        UIBezierPath *dot = [UIBezierPath bezierPathWithOvalInRect:
                              CGRectMake(centerX - unit * 1.6f,
                                         midY - unit * 1.6f,
                                         unit * 3.2f,
                                         unit * 3.2f)];
        [dot fill];
      }
      break;
    }
  }
}

@end

@interface XPPlayerProgressTrack : UIView
@property (nonatomic, assign) float progress;
@property (nonatomic, copy) void (^seekHandler)(float fraction);
@end

@implementation XPPlayerProgressTrack

- (instancetype)initWithFrame:(CGRect)frame
{
  self = [super initWithFrame:frame];
  if (self) {
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;
    self.progress = 0.0f;
  }
  return self;
}

- (void)setProgress:(float)progress
{
  _progress = MAX(0.0f, MIN(1.0f, progress));
  [self setNeedsDisplay];
}

- (CGRect)trackRect
{
  CGFloat width = CGRectGetWidth(self.bounds);
  CGFloat height = CGRectGetHeight(self.bounds);
  CGFloat barHeight = 4.0f;
  return CGRectMake(0.0f,
                    (height - barHeight) / 2.0f,
                    MAX(1.0f, width),
                    barHeight);
}

- (void)drawRect:(CGRect)rect
{
  CGContextRef context = UIGraphicsGetCurrentContext();
  if (context == NULL) {
    return;
  }
  CGRect track = [self trackRect];
  [[UIColor colorWithWhite:1.0f alpha:0.24f] setFill];
  [XPRoundedPath(track, track.size.height / 2.0f) fill];

  CGFloat played = CGRectGetWidth(track) * self.progress;
  if (played > 0.5f) {
    CGRect filled = CGRectMake(CGRectGetMinX(track),
                               CGRectGetMinY(track),
                               played,
                               CGRectGetHeight(track));
    CGContextSaveGState(context);
    [XPRoundedPath(filled, CGRectGetHeight(track) / 2.0f) addClip];
    XPDrawHorizontalGradient(context, filled, XPColorAccent(), XPColorAccentAlt());
    CGContextRestoreGState(context);
  }
  if (self.progress > 0.001f) {
    CGFloat knobX = CGRectGetMinX(track) + played;
    CGRect knob = CGRectMake(knobX - 5.0f,
                              CGRectGetMidY(track) - 5.0f,
                              10.0f,
                              10.0f);
    [[UIColor colorWithWhite:1.0f alpha:0.92f] setFill];
    [XPRoundedPath(knob, 5.0f) fill];
  }
}

- (float)fractionAtPoint:(CGPoint)point
{
  CGFloat width = CGRectGetWidth(self.bounds);
  if (width <= 0.0f) {
    return 0.0f;
  }
  float value = (float)(point.x / width);
  return MAX(0.0f, MIN(1.0f, value));
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
  UITouch *touch = touches.anyObject;
  if (touch == nil) {
    return;
  }
  self.progress = [self fractionAtPoint:[touch locationInView:self]];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
  UITouch *touch = touches.anyObject;
  if (touch == nil) {
    return;
  }
  self.progress = [self fractionAtPoint:[touch locationInView:self]];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
  UITouch *touch = touches.anyObject;
  if (touch == nil) {
    return;
  }
  float fraction = [self fractionAtPoint:[touch locationInView:self]];
  self.progress = fraction;
  if (self.seekHandler != nil) {
    self.seekHandler(fraction);
  }
}

@end

static NSString *XPPlayerClockText(double seconds)
{
  if (seconds < 0.0 || isnan(seconds)) {
    return @"--:--";
  }
  int total = (int)seconds;
  int hours = total / 3600;
  int minutes = (total % 3600) / 60;
  int rest = total % 60;
  if (hours > 0) {
    return [NSString stringWithFormat:@"%d:%02d:%02d", hours, minutes, rest];
  }
  return [NSString stringWithFormat:@"%02d:%02d", minutes, rest];
}

@interface XPPlayerControls ()
@property (nonatomic, strong) XPBackControl *backControl;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *liveLabel;
@property (nonatomic, strong) UILabel *elapsedLabel;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) XPPlayerProgressTrack *progressTrack;
@property (nonatomic, strong) XPPlayerIconButton *previousButton;
@property (nonatomic, strong) XPPlayerIconButton *playButton;
@property (nonatomic, strong) XPPlayerIconButton *nextButton;
@property (nonatomic, strong) XPPlayerIconButton *moreButton;
@end

@implementation XPPlayerControls

- (instancetype)initWithFrame:(CGRect)frame
{
  self = [super initWithFrame:frame];
  if (self) {
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;

    self.backControl = [[XPBackControl alloc] initWithFrame:CGRectZero];
    [self.backControl addTarget:self
                          action:@selector(closeTapped:)
                forControlEvents:UIControlEventTouchUpInside];
    self.backControl.accessibilityLabel = @"Volver";
    [self addSubview:self.backControl];

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.titleLabel.font = XPFontMedium(15.0f);
    self.titleLabel.textColor = XPColorTextPrimary();
    self.titleLabel.numberOfLines = 1;
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self addSubview:self.titleLabel];

    self.subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.subtitleLabel.font = XPFontCaption(11.5f);
    self.subtitleLabel.textColor = XPColorTextMuted();
    self.subtitleLabel.numberOfLines = 1;
    self.subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self addSubview:self.subtitleLabel];

    self.liveLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.liveLabel.font = XPFontCaption(10.5f);
    self.liveLabel.textColor = [UIColor whiteColor];
    self.liveLabel.textAlignment = NSTextAlignmentCenter;
    self.liveLabel.text = @"EN VIVO";
    self.liveLabel.backgroundColor = [XPColorAccent() colorWithAlphaComponent:0.92f];
    self.liveLabel.layer.cornerRadius = 8.0f;
    self.liveLabel.layer.masksToBounds = YES;
    self.liveLabel.hidden = YES;
    [self addSubview:self.liveLabel];

    self.elapsedLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.elapsedLabel.font = XPFontCaption(11.0f);
    self.elapsedLabel.textColor = XPColorTextMuted();
    self.elapsedLabel.text = @"00:00";
    [self addSubview:self.elapsedLabel];

    self.durationLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.durationLabel.font = XPFontCaption(11.0f);
    self.durationLabel.textColor = XPColorTextMuted();
    self.durationLabel.textAlignment = NSTextAlignmentRight;
    self.durationLabel.text = @"--:--";
    [self addSubview:self.durationLabel];

    self.progressTrack = [[XPPlayerProgressTrack alloc] initWithFrame:CGRectZero];
    __weak XPPlayerControls *weakSelf = self;
    self.progressTrack.seekHandler = ^(float fraction) {
      XPPlayerControls *strongSelf = weakSelf;
      if (strongSelf != nil && strongSelf.seekHandler != nil) {
        strongSelf.seekHandler(fraction);
      }
    };
    self.progressTrack.accessibilityLabel = @"Progreso";
    [self addSubview:self.progressTrack];

    self.previousButton = [[XPPlayerIconButton alloc] initWithFrame:CGRectZero];
    self.previousButton.icon = XPPlayerControlIconPreviousChapter;
    self.previousButton.accessibilityLabel = @"Capítulo anterior";
    [self.previousButton addTarget:self
                             action:@selector(previousTapped:)
                   forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.previousButton];

    self.playButton = [[XPPlayerIconButton alloc] initWithFrame:CGRectZero];
    self.playButton.icon = XPPlayerControlIconPlay;
    self.playButton.emphasized = YES;
    self.playButton.accessibilityLabel = @"Reproducir o pausar";
    [self.playButton addTarget:self
                         action:@selector(playPauseTapped:)
               forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.playButton];

    self.nextButton = [[XPPlayerIconButton alloc] initWithFrame:CGRectZero];
    self.nextButton.icon = XPPlayerControlIconNextChapter;
    self.nextButton.accessibilityLabel = @"Capítulo siguiente";
    [self.nextButton addTarget:self
                         action:@selector(nextTapped:)
               forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.nextButton];

    self.moreButton = [[XPPlayerIconButton alloc] initWithFrame:CGRectZero];
    self.moreButton.icon = XPPlayerControlIconMore;
    self.moreButton.accessibilityLabel = @"Más opciones";
    [self.moreButton addTarget:self
                         action:@selector(moreTapped:)
               forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.moreButton];

    self.progress = 0.0f;
    self.playing = YES;
  }
  return self;
}

- (void)setTitleText:(NSString *)titleText
{
  _titleText = [titleText copy];
  self.titleLabel.text = _titleText ?: @"";
}

- (void)setSubtitleText:(NSString *)subtitleText
{
  _subtitleText = [subtitleText copy];
  self.subtitleLabel.text = _subtitleText ?: @"";
}

- (void)setElapsedTime:(double)elapsedTime
{
  _elapsedTime = elapsedTime;
  self.elapsedLabel.text = XPPlayerClockText(elapsedTime);
}

- (void)setDuration:(double)duration
{
  _duration = duration;
  self.durationLabel.text = duration > 0.0 ? XPPlayerClockText(duration) : @"--:--";
}

- (void)setProgress:(float)progress
{
  _progress = MAX(0.0f, MIN(1.0f, progress));
  self.progressTrack.progress = _progress;
}

- (void)setPlaying:(BOOL)playing
{
  _playing = playing;
  self.playButton.icon = playing ? XPPlayerControlIconPause : XPPlayerControlIconPlay;
  self.playButton.accessibilityLabel = playing ? @"Pausar" : @"Reproducir";
}

- (void)setLiveStream:(BOOL)liveStream
{
  _liveStream = liveStream;
  self.liveLabel.hidden = !liveStream;
  self.progressTrack.hidden = liveStream;
  self.elapsedLabel.hidden = liveStream;
  self.durationLabel.hidden = liveStream;
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  CGFloat width = CGRectGetWidth(self.bounds);
  CGFloat height = CGRectGetHeight(self.bounds);
  CGFloat margin = 14.0f;

  self.backControl.frame = CGRectMake(margin, 10.0f, 36.0f, 36.0f);
  CGFloat textLeft = margin + 46.0f;
  CGFloat textWidth = MAX(40.0f, width - textLeft - margin - 54.0f);
  self.titleLabel.frame = CGRectMake(textLeft, 10.0f, textWidth, 20.0f);
  self.subtitleLabel.frame = CGRectMake(textLeft, 30.0f, textWidth, 16.0f);
  self.liveLabel.frame = CGRectMake(width - margin - 58.0f, 15.0f, 58.0f, 16.0f);

  CGFloat timesY = height - 58.0f;
  self.elapsedLabel.frame = CGRectMake(margin, timesY, 50.0f, 15.0f);
  self.durationLabel.frame = CGRectMake(width - margin - 50.0f, timesY, 50.0f, 15.0f);
  CGFloat trackLeft = margin + 54.0f;
  CGFloat trackRight = width - margin - 54.0f;
  self.progressTrack.frame = CGRectMake(trackLeft,
                                        timesY - 5.0f,
                                        MAX(30.0f, trackRight - trackLeft),
                                        24.0f);

  CGFloat rowY = height - 48.0f;
  self.previousButton.frame = CGRectMake(margin, rowY, 38.0f, 38.0f);
  self.playButton.frame = CGRectMake(margin + 48.0f, rowY - 3.0f, 44.0f, 44.0f);
  self.nextButton.frame = CGRectMake(margin + 102.0f, rowY, 38.0f, 38.0f);
  self.moreButton.frame = CGRectMake(width - margin - 38.0f, rowY, 38.0f, 38.0f);
}

- (void)drawRect:(CGRect)rect
{
  CGContextRef context = UIGraphicsGetCurrentContext();
  if (context == NULL) {
    return;
  }
  CGFloat width = CGRectGetWidth(self.bounds);
  CGFloat height = CGRectGetHeight(self.bounds);

  CGRect topBand = CGRectMake(0.0f, 0.0f, width, 86.0f);
  XPDrawVerticalGradient(context,
                         topBand,
                         [UIColor colorWithWhite:0.0f alpha:0.80f],
                         [UIColor colorWithWhite:0.0f alpha:0.0f]);

  CGFloat bandHeight = MIN(160.0f, height);
  CGRect bottomBand = CGRectMake(0.0f, height - bandHeight, width, bandHeight);
  XPDrawVerticalGradient(context,
                         bottomBand,
                         [UIColor colorWithWhite:0.0f alpha:0.0f],
                         [UIColor colorWithWhite:0.0f alpha:0.88f]);
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event
{
  for (UIView *subview in self.subviews) {
    if (subview.hidden || !subview.userInteractionEnabled) {
      continue;
    }
    if (CGRectContainsPoint(subview.frame, point)) {
      return YES;
    }
  }
  return NO;
}

- (void)closeTapped:(id)sender
{
  if (self.closeHandler != nil) {
    self.closeHandler();
  }
}

- (void)playPauseTapped:(id)sender
{
  if (self.playPauseHandler != nil) {
    self.playPauseHandler();
  }
}

- (void)previousTapped:(id)sender
{
  if (self.previousChapterHandler != nil) {
    self.previousChapterHandler();
  }
}

- (void)nextTapped:(id)sender
{
  if (self.nextChapterHandler != nil) {
    self.nextChapterHandler();
  }
}

- (void)moreTapped:(id)sender
{
  if (self.moreHandler != nil) {
    self.moreHandler();
  }
}

@end
