#import "XPOptionsPanel.h"

#import "XPButton.h"
#import "XPChipButton.h"
#import "XPDecoder.h"
#import "XPTheme.h"
#import "XPDrawnLabel.h"
#import "XPDrawnScrollView.h"

#import <math.h>

typedef NS_ENUM(NSInteger, XPOptionRowKind) {
  XPOptionRowKindSection,
  XPOptionRowKindOption,
  XPOptionRowKindChips,
  XPOptionRowKindInformation
};

@interface XPOptionRow : NSObject
@property (nonatomic, strong) UIView *view;
@property (nonatomic, assign) CGFloat height;
@property (nonatomic, assign) XPOptionRowKind kind;
@end

@implementation XPOptionRow
@end

@interface XPOptionsPanel () {
  XPDrawnLabel *titleLabel;
  XPButton *closeButton;
  XPDrawnScrollView *scrollView;
  NSMutableArray *rows;
  NSMutableArray *audioButtons;
  NSMutableArray *subtitleButtons;
  NSMutableArray *qualityButtons;
  NSMutableArray *rateChips;
}
@end

@implementation XPOptionsPanel

- (instancetype)initWithFrame:(CGRect)frame
{
  self = [super initWithFrame:frame];
  if (self) {
    self.backgroundColor = [XPColorSurface() colorWithAlphaComponent:0.95f];
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;

    rows = [NSMutableArray array];
    audioButtons = [NSMutableArray array];
    subtitleButtons = [NSMutableArray array];
    qualityButtons = [NSMutableArray array];
    rateChips = [NSMutableArray array];

    titleLabel = [[XPDrawnLabel alloc] initWithFrame:CGRectZero];
    titleLabel.font = XPFontMedium(14.0f);
    titleLabel.textColor = XPColorTextPrimary();
    titleLabel.text = @"Opciones";
    [self addSubview:titleLabel];

    closeButton = [[XPButton alloc] initWithTitle:@"Cerrar" style:XPButtonStyleGhost];
    [closeButton addTarget:self
                     action:@selector(closeTapped:)
           forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:closeButton];

    scrollView = [[XPDrawnScrollView alloc] initWithFrame:CGRectZero];
    scrollView.scrollsHorizontally = NO;
    scrollView.scrollsVertically = YES;
    [self addSubview:scrollView];

    self.selectedAudioIndex = -1;
    self.selectedSubtitleIndex = -1;
    self.selectedQualityIndex = -1;
    self.playbackRate = 1.0f;
  }
  return self;
}

- (void)setAudioTracks:(NSArray *)audioTracks
{
  _audioTracks = [audioTracks copy];
  [self rebuild];
}

- (void)setSubtitleTracks:(NSArray *)subtitleTracks
{
  _subtitleTracks = [subtitleTracks copy];
  [self rebuild];
}

- (void)setQualityTitles:(NSArray *)qualityTitles
{
  _qualityTitles = [qualityTitles copy];
  [self rebuild];
}

- (void)setSelectedQualityIndex:(NSInteger)selectedQualityIndex
{
  _selectedQualityIndex = selectedQualityIndex;
  [self updateSelections];
}

- (void)setSelectedAudioIndex:(NSInteger)selectedAudioIndex
{
  _selectedAudioIndex = selectedAudioIndex;
  [self updateSelections];
}

- (void)setSelectedSubtitleIndex:(NSInteger)selectedSubtitleIndex
{
  _selectedSubtitleIndex = selectedSubtitleIndex;
  [self updateSelections];
}

- (void)setPlaybackRate:(float)playbackRate
{
  _playbackRate = playbackRate;
  [self updateSelections];
}

- (void)setInformationText:(NSString *)informationText
{
  _informationText = [informationText copy];
  [self rebuild];
}

- (NSString *)titleForTrack:(XPTrackInfo *)track
{
  NSMutableString *title = [NSMutableString string];
  NSString *name = track.languageName.length > 0 ? track.languageName : @"Pista";
  [title appendString:name];
  if (track.title.length > 0) {
    [title appendFormat:@" · %@", track.title];
  }
  if (track.codecName.length > 0) {
    [title appendFormat:@" · %@", [track.codecName uppercaseString]];
  }
  if (track.original) {
    [title appendString:@" · Original"];
  }
  if (!track.available) {
    [title appendString:@" · sin decodificador"];
  }
  return title;
}

- (XPOptionRow *)addSectionWithTitle:(NSString *)text
{
  XPDrawnLabel *label = [[XPDrawnLabel alloc] initWithFrame:CGRectZero];
  label.font = XPFontCaption(10.5f);
  label.textColor = XPColorTextMuted();
  label.text = text;
  [scrollView addSubview:label];
  XPOptionRow *row = [[XPOptionRow alloc] init];
  row.view = label;
  row.height = 20.0f;
  row.kind = XPOptionRowKindSection;
  [rows addObject:row];
  return row;
}

- (void)rebuild
{
  for (XPOptionRow *row in rows) {
    [row.view removeFromSuperview];
  }
  [rows removeAllObjects];
  [audioButtons removeAllObjects];
  [subtitleButtons removeAllObjects];
  [qualityButtons removeAllObjects];
  [rateChips removeAllObjects];

  if (self.qualityTitles.count > 0) {
    [self addSectionWithTitle:@"CALIDAD"];
    for (NSUInteger index = 0; index < self.qualityTitles.count; index++) {
      id item = self.qualityTitles[index];
      NSString *text = [item isKindOfClass:[NSString class]] ? (NSString *)item : @"";
      XPButton *button = [[XPButton alloc] initWithTitle:text style:XPButtonStyleGhost];
      button.tag = (NSInteger)index;
      [button addTarget:self
                 action:@selector(qualityTapped:)
       forControlEvents:UIControlEventTouchUpInside];
      [scrollView addSubview:button];
      XPOptionRow *row = [[XPOptionRow alloc] init];
      row.view = button;
      row.height = 30.0f;
      row.kind = XPOptionRowKindOption;
      [rows addObject:row];
      [qualityButtons addObject:button];
    }
  }

  [self addSectionWithTitle:@"AUDIO"];
  if (self.audioTracks.count == 0) {
    XPDrawnLabel *empty = [[XPDrawnLabel alloc] initWithFrame:CGRectZero];
    empty.font = XPFontBody(13.0f);
    empty.textColor = XPColorTextMuted();
    empty.text = @"Esta reproducción no permite cambiar el idioma del audio";
    [scrollView addSubview:empty];
    XPOptionRow *row = [[XPOptionRow alloc] init];
    row.view = empty;
    row.height = 26.0f;
    row.kind = XPOptionRowKindOption;
    [rows addObject:row];
  } else {
    for (XPTrackInfo *track in self.audioTracks) {
      if (![track isKindOfClass:[XPTrackInfo class]]) {
        continue;
      }
      XPButton *button = [[XPButton alloc] initWithTitle:[self titleForTrack:track]
                                                  style:XPButtonStyleGhost];
      button.tag = track.streamIndex;
      button.enabled = track.available;
      [button addTarget:self
                  action:@selector(audioTapped:)
        forControlEvents:UIControlEventTouchUpInside];
      [scrollView addSubview:button];
      XPOptionRow *row = [[XPOptionRow alloc] init];
      row.view = button;
      row.height = 30.0f;
      row.kind = XPOptionRowKindOption;
      [rows addObject:row];
      [audioButtons addObject:button];
    }
  }

  [self addSectionWithTitle:@"SUBTÍTULOS"];
  XPButton *offButton = [[XPButton alloc] initWithTitle:@"Desactivados" style:XPButtonStyleGhost];
  offButton.tag = -1;
  [offButton addTarget:self
                action:@selector(subtitleTapped:)
      forControlEvents:UIControlEventTouchUpInside];
  [scrollView addSubview:offButton];
  XPOptionRow *offRow = [[XPOptionRow alloc] init];
  offRow.view = offButton;
  offRow.height = 30.0f;
  offRow.kind = XPOptionRowKindOption;
  [rows addObject:offRow];
  [subtitleButtons addObject:offButton];

  if (self.subtitleTracks.count == 0) {
    XPDrawnLabel *empty = [[XPDrawnLabel alloc] initWithFrame:CGRectZero];
    empty.font = XPFontBody(13.0f);
    empty.textColor = XPColorTextMuted();
    empty.text = @"Este contenido no incluye pistas de subtítulos";
    [scrollView addSubview:empty];
    XPOptionRow *row = [[XPOptionRow alloc] init];
    row.view = empty;
    row.height = 26.0f;
    row.kind = XPOptionRowKindOption;
    [rows addObject:row];
  } else {
    for (XPTrackInfo *track in self.subtitleTracks) {
      if (![track isKindOfClass:[XPTrackInfo class]]) {
        continue;
      }
      NSMutableString *title = [NSMutableString stringWithString:[self titleForTrack:track]];
      XPButton *button = [[XPButton alloc] initWithTitle:title style:XPButtonStyleGhost];
      button.tag = track.streamIndex;
      button.enabled = track.available;
      [button addTarget:self
                  action:@selector(subtitleTapped:)
        forControlEvents:UIControlEventTouchUpInside];
      [scrollView addSubview:button];
      XPOptionRow *row = [[XPOptionRow alloc] init];
      row.view = button;
      row.height = 30.0f;
      row.kind = XPOptionRowKindOption;
      [rows addObject:row];
      [subtitleButtons addObject:button];
    }
  }

  [self addSectionWithTitle:@"VELOCIDAD"];
  XPDrawnScrollView *chipScroll = [[XPDrawnScrollView alloc] initWithFrame:CGRectZero];
  chipScroll.scrollsHorizontally = YES;
  chipScroll.scrollsVertically = NO;
  [scrollView addSubview:chipScroll];
  XPOptionRow *chipRow = [[XPOptionRow alloc] init];
  chipRow.view = chipScroll;
  chipRow.height = 34.0f;
  chipRow.kind = XPOptionRowKindChips;
  [rows addObject:chipRow];

  float rates[6] = { 0.5f, 0.75f, 1.0f, 1.25f, 1.5f, 2.0f };
  CGFloat offset = 0.0f;
  for (int index = 0; index < 6; index++) {
    float value = rates[index];
    NSString *title = [NSString stringWithFormat:@"%.2gx", value];
    XPChipButton *chip = [[XPChipButton alloc] initWithTitle:title];
    chip.tag = index;
    [chip addTarget:self
              action:@selector(rateTapped:)
    forControlEvents:UIControlEventTouchUpInside];
    [chipScroll addSubview:chip];
    chip.frame = CGRectMake(offset, 2.0f, 56.0f, 28.0f);
    offset += 62.0f;
    [rateChips addObject:chip];
  }
  chipScroll.contentSize = CGSizeMake(MAX(1.0f, offset), 34.0f);

  [self addSectionWithTitle:@"INFORMACIÓN"];
  XPDrawnLabel *info = [[XPDrawnLabel alloc] initWithFrame:CGRectZero];
  info.font = XPFontCaption(11.5f);
  info.textColor = XPColorTextMuted();
  info.text = self.informationText.length > 0 ? self.informationText : @"Sin datos del flujo";
  info.numberOfLines = 2;
  [scrollView addSubview:info];
  XPOptionRow *infoRow = [[XPOptionRow alloc] init];
  infoRow.view = info;
  infoRow.height = 32.0f;
  infoRow.kind = XPOptionRowKindInformation;
  [rows addObject:infoRow];

  [self updateSelections];
  [self setNeedsLayout];
}

- (void)updateSelections
{
  for (XPButton *button in qualityButtons) {
    button.buttonStyle = (button.tag == self.selectedQualityIndex)
      ? XPButtonStylePrimary
      : XPButtonStyleGhost;
  }
  for (XPButton *button in audioButtons) {
    button.buttonStyle = (button.tag == self.selectedAudioIndex)
      ? XPButtonStylePrimary
      : XPButtonStyleGhost;
  }
  for (XPButton *button in subtitleButtons) {
    button.buttonStyle = (button.tag == self.selectedSubtitleIndex)
      ? XPButtonStylePrimary
      : XPButtonStyleGhost;
  }
  float rates[6] = { 0.5f, 0.75f, 1.0f, 1.25f, 1.5f, 2.0f };
  for (XPChipButton *chip in rateChips) {
    NSInteger index = chip.tag;
    if (index < 0 || index > 5) {
      continue;
    }
    chip.selected = fabsf(rates[index] - self.playbackRate) < 0.01f;
  }
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  CGFloat width = CGRectGetWidth(self.bounds);
  CGFloat height = CGRectGetHeight(self.bounds);
  CGFloat margin = 12.0f;

  titleLabel.frame = CGRectMake(margin, 9.0f, MAX(40.0f, width - 120.0f), 18.0f);
  closeButton.frame = CGRectMake(width - margin - 76.0f, 6.0f, 76.0f, 26.0f);

  CGFloat scrollTop = 38.0f;
  scrollView.frame = CGRectMake(0.0f, scrollTop, width, MAX(10.0f, height - scrollTop));

  CGFloat y = 4.0f;
  CGFloat contentWidth = MAX(20.0f, width - margin * 2.0f);
  for (XPOptionRow *row in rows) {
    if (row.kind == XPOptionRowKindChips) {
      row.view.frame = CGRectMake(margin, y, contentWidth, row.height);
      for (XPChipButton *chip in rateChips) {
        chip.frame = CGRectMake(chip.frame.origin.x, 2.0f, chip.frame.size.width, chip.frame.size.height);
      }
    } else {
      row.view.frame = CGRectMake(margin, y, contentWidth, row.height);
    }
    y += row.height + 6.0f;
  }
  scrollView.contentSize = CGSizeMake(width, y + 4.0f);
}

- (void)drawRect:(CGRect)rect
{
  CGContextRef context = UIGraphicsGetCurrentContext();
  if (context == NULL) {
    return;
  }
  [XPColorDivider() setFill];
  CGContextFillRect(context, CGRectMake(0.0f, 0.0f, CGRectGetWidth(self.bounds), 1.0f));
}

- (void)audioTapped:(id)sender
{
  XPButton *button = (XPButton *)sender;
  if (self.audioSelectionHandler != nil) {
    self.audioSelectionHandler(button.tag);
  }
}

- (void)qualityTapped:(id)sender
{
  XPButton *button = (XPButton *)sender;
  if (self.qualitySelectionHandler != nil) {
    self.qualitySelectionHandler(button.tag);
  }
}

- (void)subtitleTapped:(id)sender
{
  XPButton *button = (XPButton *)sender;
  if (self.subtitleSelectionHandler != nil) {
    self.subtitleSelectionHandler(button.tag);
  }
}

- (void)rateTapped:(id)sender
{
  XPChipButton *chip = (XPChipButton *)sender;
  float rates[6] = { 0.5f, 0.75f, 1.0f, 1.25f, 1.5f, 2.0f };
  NSInteger index = chip.tag;
  if (index < 0 || index > 5) {
    return;
  }
  if (self.rateSelectionHandler != nil) {
    self.rateSelectionHandler(rates[index]);
  }
}

- (void)closeTapped:(id)sender
{
  if (self.closeHandler != nil) {
    self.closeHandler();
  }
}

@end
