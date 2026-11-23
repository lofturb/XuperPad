//
//  XPSettingsViewController.m
//

#import "XPSettingsViewController.h"
#import "XPStore.h"
#import "XPTheme.h"
#import "XPButton.h"
#import "XPChipButton.h"
#import "XPDrawnLabel.h"
#import "XPDrawnScrollView.h"

@interface XPSettingsViewController ()
@property (nonatomic, strong) XPDrawnScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) XPDrawnLabel *headerLabel;
@property (nonatomic, strong) XPDrawnLabel *aspectHeader;
@property (nonatomic, strong) XPDrawnLabel *audioHeader;
@property (nonatomic, strong) XPDrawnLabel *dataHeader;
@property (nonatomic, strong) XPDrawnLabel *statusLabel;
@property (nonatomic, strong) NSArray *aspectChips;
@property (nonatomic, strong) NSArray *audioChips;
@property (nonatomic, strong) XPButton *clearHistoryButton;
@property (nonatomic, strong) XPButton *clearFavoritesButton;
@end

@implementation XPSettingsViewController

- (void)viewDidLoad
{
  [super viewDidLoad];
  self.view.backgroundColor = XPColorBackground();
  self.edgesForExtendedLayout = UIRectEdgeAll;

  self.scrollView = [[XPDrawnScrollView alloc] initWithFrame:self.view.bounds];
  self.scrollView.backgroundColor = [UIColor clearColor];
  self.scrollView.scrollsVertically = YES;
  self.scrollView.scrollsHorizontally = NO;
  [self.view addSubview:self.scrollView];

  self.contentView = [[UIView alloc] initWithFrame:CGRectZero];
  [self.scrollView addSubview:self.contentView];

  self.headerLabel = [[XPDrawnLabel alloc] initWithFrame:CGRectZero];
  self.headerLabel.font = XPFontDisplay(22.0f);
  self.headerLabel.textColor = XPColorTextPrimary();
  self.headerLabel.text = self.screenTitle ?: @"Ajustes";
  [self.contentView addSubview:self.headerLabel];

  self.aspectHeader = [[XPDrawnLabel alloc] initWithFrame:CGRectZero];
  self.aspectHeader.font = XPFontMedium(15.0f);
  self.aspectHeader.textColor = XPColorTextPrimary();
  self.aspectHeader.text = @"Aspecto de video";
  [self.contentView addSubview:self.aspectHeader];

  NSArray *aspectTitles = @[ @"Ajustar", @"Rellenar", @"Estirar" ];
  NSMutableArray *aspectChips = [NSMutableArray array];
  for (NSUInteger index = 0; index < aspectTitles.count; index++) {
    XPChipButton *chip = [[XPChipButton alloc] initWithTitle:aspectTitles[index]];
    chip.tag = (NSInteger)index;
    [chip addTarget:self
             action:@selector(aspectChipTapped:)
   forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:chip];
    [aspectChips addObject:chip];
  }
  self.aspectChips = aspectChips;

  self.audioHeader = [[XPDrawnLabel alloc] initWithFrame:CGRectZero];
  self.audioHeader.font = XPFontMedium(15.0f);
  self.audioHeader.textColor = XPColorTextPrimary();
  self.audioHeader.text = @"Idioma de audio";
  [self.contentView addSubview:self.audioHeader];

  NSArray *audioTitles = @[ @"Espanol", @"Original" ];
  NSMutableArray *audioChips = [NSMutableArray array];
  for (NSUInteger index = 0; index < audioTitles.count; index++) {
    XPChipButton *chip = [[XPChipButton alloc] initWithTitle:audioTitles[index]];
    chip.tag = (NSInteger)index;
    [chip addTarget:self
             action:@selector(audioChipTapped:)
   forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:chip];
    [audioChips addObject:chip];
  }
  self.audioChips = audioChips;

  self.dataHeader = [[XPDrawnLabel alloc] initWithFrame:CGRectZero];
  self.dataHeader.font = XPFontMedium(15.0f);
  self.dataHeader.textColor = XPColorTextPrimary();
  self.dataHeader.text = @"Mis datos";
  [self.contentView addSubview:self.dataHeader];

  self.clearHistoryButton = [[XPButton alloc] initWithTitle:@"Borrar historial"
                                                      style:XPButtonStyleGhost];
  [self.clearHistoryButton addTarget:self
                              action:@selector(clearHistoryTapped:)
                    forControlEvents:UIControlEventTouchUpInside];
  [self.contentView addSubview:self.clearHistoryButton];

  self.clearFavoritesButton = [[XPButton alloc] initWithTitle:@"Vaciar guardados"
                                                        style:XPButtonStyleGhost];
  [self.clearFavoritesButton addTarget:self
                                action:@selector(clearFavoritesTapped:)
                      forControlEvents:UIControlEventTouchUpInside];
  [self.contentView addSubview:self.clearFavoritesButton];

  self.statusLabel = [[XPDrawnLabel alloc] initWithFrame:CGRectZero];
  self.statusLabel.font = XPFontCaption(11.0f);
  self.statusLabel.textColor = XPColorAccent();
  self.statusLabel.text = @"";
  [self.contentView addSubview:self.statusLabel];

  [self reloadSelections];
}

- (void)reloadSelections
{
  XPAspectMode mode = [[XPStore sharedStore] aspectMode];
  for (XPChipButton *chip in self.aspectChips) {
    chip.selected = ((NSInteger)mode == chip.tag);
  }
  NSString *audio = [[XPStore sharedStore] preferredAudioLanguage];
  for (XPChipButton *chip in self.audioChips) {
    BOOL wantsOriginal = (audio.length == 0);
    chip.selected = (chip.tag == 1) ? wantsOriginal : !wantsOriginal;
  }
}

- (void)aspectChipTapped:(XPChipButton *)sender
{
  [[XPStore sharedStore] setAspectMode:(XPAspectMode)sender.tag];
  [self reloadSelections];
}

- (void)audioChipTapped:(XPChipButton *)sender
{
  NSString *language = (sender.tag == 0) ? @"es" : @"";
  [[XPStore sharedStore] setPreferredAudioLanguage:language];
  [self reloadSelections];
}

- (void)clearHistoryTapped:(id)sender
{
  [[XPStore sharedStore] clearHistory];
  self.statusLabel.text = @"Historial borrado";
}

- (void)clearFavoritesTapped:(id)sender
{
  NSArray *favorites = [[XPStore sharedStore] favoriteTitles];
  for (NSDictionary *entry in favorites) {
    [[XPStore sharedStore] removeFavoriteWithId:entry[@"id"]];
  }
  self.statusLabel.text = @"Guardados vaciados";
}

- (void)viewDidLayoutSubviews
{
  [super viewDidLayoutSubviews];
  CGFloat width = CGRectGetWidth(self.view.bounds);
  CGFloat height = CGRectGetHeight(self.view.bounds);
  CGFloat margin = 14.0f;
  CGFloat inner = width - margin * 2.0f;

  self.scrollView.frame = CGRectMake(0, 0, width, height);

  CGFloat cursor = 24.0f;
  self.headerLabel.frame = CGRectMake(margin, cursor, inner, 28.0f);
  cursor += 42.0f;

  self.aspectHeader.frame = CGRectMake(margin, cursor, inner, 20.0f);
  cursor += 28.0f;
  CGFloat chipGap = 8.0f;
  CGFloat chipWidth = (inner - chipGap * 2.0f) / 3.0f;
  for (NSUInteger index = 0; index < self.aspectChips.count; index++) {
    XPChipButton *chip = self.aspectChips[index];
    chip.frame = CGRectMake(margin + index * (chipWidth + chipGap), cursor,
                            chipWidth, 32.0f);
  }
  cursor += 32.0f + 28.0f;

  self.audioHeader.frame = CGRectMake(margin, cursor, inner, 20.0f);
  cursor += 28.0f;
  CGFloat audioWidth = (inner - chipGap) / 2.0f;
  for (NSUInteger index = 0; index < self.audioChips.count; index++) {
    XPChipButton *chip = self.audioChips[index];
    chip.frame = CGRectMake(margin + index * (audioWidth + chipGap), cursor,
                            audioWidth, 32.0f);
  }
  cursor += 32.0f + 30.0f;

  self.dataHeader.frame = CGRectMake(margin, cursor, inner, 20.0f);
  cursor += 28.0f;
  self.clearHistoryButton.frame = CGRectMake(margin, cursor, inner, 44.0f);
  cursor += 44.0f + 10.0f;
  self.clearFavoritesButton.frame = CGRectMake(margin, cursor, inner, 44.0f);
  cursor += 44.0f + 12.0f;

  self.statusLabel.frame = CGRectMake(margin, cursor, inner, 16.0f);
  cursor += 34.0f;

  self.contentView.frame = CGRectMake(0, 0, width, cursor);
  self.scrollView.contentSize = CGSizeMake(width, cursor);
}

@end
