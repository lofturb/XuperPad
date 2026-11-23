//
//  XPStore.m
//

#import "XPStore.h"

static NSString *const XPStoreHistoryKey = @"xp.store.history";
static NSString *const XPStoreFavoritesKey = @"xp.store.favorites";
static NSString *const XPStoreAudioKey = @"xp.store.audioLanguage";
static NSString *const XPStoreSubtitleKey = @"xp.store.subtitleLanguage";
static NSString *const XPStoreAspectKey = @"xp.store.aspectMode";

static NSUInteger const XPStoreHistoryLimit = 100;

@implementation XPStore

+ (instancetype)sharedStore
{
  static XPStore *store = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    store = [[XPStore alloc] init];
  });
  return store;
}

#pragma mark - Ajustes

- (NSString *)preferredAudioLanguage
{
  NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:XPStoreAudioKey];
  return value ?: @"";
}

- (void)setPreferredAudioLanguage:(NSString *)preferredAudioLanguage
{
  [[NSUserDefaults standardUserDefaults] setObject:(preferredAudioLanguage ?: @"") forKey:XPStoreAudioKey];
}

- (NSString *)preferredSubtitleLanguage
{
  NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:XPStoreSubtitleKey];
  return value ?: @"";
}

- (void)setPreferredSubtitleLanguage:(NSString *)preferredSubtitleLanguage
{
  [[NSUserDefaults standardUserDefaults] setObject:(preferredSubtitleLanguage ?: @"") forKey:XPStoreSubtitleKey];
}

- (XPAspectMode)aspectMode
{
  NSInteger value = [[NSUserDefaults standardUserDefaults] integerForKey:XPStoreAspectKey];
  if (value < XPAspectModeFit || value > XPAspectModeStretch) {
    return XPAspectModeFit;
  }
  return (XPAspectMode)value;
}

- (void)setAspectMode:(XPAspectMode)aspectMode
{
  [[NSUserDefaults standardUserDefaults] setInteger:aspectMode forKey:XPStoreAspectKey];
}

#pragma mark - Historial

- (NSArray *)historyEntries
{
  NSArray *stored = [[NSUserDefaults standardUserDefaults] arrayForKey:XPStoreHistoryKey];
  return stored ?: @[];
}

- (void)saveHistoryEntries:(NSArray *)entries
{
  [[NSUserDefaults standardUserDefaults] setObject:entries forKey:XPStoreHistoryKey];
}

- (NSDictionary *)historyEntryForId:(NSString *)contentId
{
  if (contentId.length == 0) {
    return nil;
  }
  for (NSDictionary *entry in [self historyEntries]) {
    if ([entry[@"id"] isEqual:contentId]) {
      return entry;
    }
  }
  return nil;
}

- (void)recordPlaybackWithId:(NSString *)contentId
                        name:(NSString *)name
                    isSeries:(BOOL)isSeries
                      poster:(NSString *)poster
                    backdrop:(NSString *)backdrop
                    chapters:(NSArray *)chapters
            currentChapter:(NSInteger)currentChapter
                  position:(double)position
                  duration:(double)duration
{
  if (contentId.length == 0) {
    return;
  }

  NSMutableArray *entries = [[self historyEntries] mutableCopy];
  NSMutableArray *filtered = [NSMutableArray array];
  for (NSDictionary *entry in entries) {
    if (![entry[@"id"] isEqual:contentId]) {
      [filtered addObject:entry];
    }
  }

  NSMutableDictionary *record = [NSMutableDictionary dictionary];
  record[@"id"] = contentId;
  record[@"name"] = name ?: @"";
  record[@"series"] = @(isSeries);
  record[@"poster"] = poster ?: @"";
  record[@"backdrop"] = backdrop ?: @"";
  record[@"chapters"] = chapters ?: @[];
  record[@"chapterIndex"] = @(currentChapter);
  record[@"position"] = @(position > 0 ? position : 0);
  record[@"duration"] = @(duration > 0 ? duration : 0);
  record[@"updatedAt"] = @([[NSDate date] timeIntervalSince1970]);

  [filtered insertObject:record atIndex:0];
  while (filtered.count > XPStoreHistoryLimit) {
    [filtered removeLastObject];
  }
  [self saveHistoryEntries:filtered];
}

- (void)removeHistoryForId:(NSString *)contentId
{
  if (contentId.length == 0) {
    return;
  }
  NSMutableArray *filtered = [NSMutableArray array];
  for (NSDictionary *entry in [self historyEntries]) {
    if (![entry[@"id"] isEqual:contentId]) {
      [filtered addObject:entry];
    }
  }
  [self saveHistoryEntries:filtered];
}

- (void)clearHistory
{
  [self saveHistoryEntries:@[]];
}

#pragma mark - Favoritos

- (NSArray *)favoriteTitles
{
  NSArray *stored = [[NSUserDefaults standardUserDefaults] arrayForKey:XPStoreFavoritesKey];
  return stored ?: @[];
}

- (void)saveFavoriteTitles:(NSArray *)titles
{
  [[NSUserDefaults standardUserDefaults] setObject:titles forKey:XPStoreFavoritesKey];
}

- (BOOL)isFavoriteWithId:(NSString *)contentId
{
  if (contentId.length == 0) {
    return NO;
  }
  for (NSDictionary *entry in [self favoriteTitles]) {
    if ([entry[@"id"] isEqual:contentId]) {
      return YES;
    }
  }
  return NO;
}

- (void)toggleFavoriteWithTitle:(NSDictionary *)title
{
  NSString *contentId = title[@"id"];
  if (contentId.length == 0) {
    return;
  }

  NSMutableArray *titles = [NSMutableArray array];
  BOOL alreadyFavorite = NO;
  for (NSDictionary *entry in [self favoriteTitles]) {
    if ([entry[@"id"] isEqual:contentId]) {
      alreadyFavorite = YES;
      continue;
    }
    [titles addObject:entry];
  }

  if (!alreadyFavorite) {
    NSMutableDictionary *record = [NSMutableDictionary dictionary];
    record[@"id"] = contentId;
    record[@"name"] = title[@"name"] ?: @"";
    record[@"poster"] = title[@"poster"] ?: @"";
    record[@"backdrop"] = title[@"backdrop"] ?: @"";
    record[@"series"] = @([title[@"series"] boolValue]);
    record[@"kind"] = title[@"kind"] ?: @"";
    record[@"addedAt"] = @([[NSDate date] timeIntervalSince1970]);
    [titles insertObject:record atIndex:0];
  }

  [self saveFavoriteTitles:titles];
}

- (void)removeFavoriteWithId:(NSString *)contentId
{
  if (contentId.length == 0) {
    return;
  }
  NSMutableArray *filtered = [NSMutableArray array];
  for (NSDictionary *entry in [self favoriteTitles]) {
    if (![entry[@"id"] isEqual:contentId]) {
      [filtered addObject:entry];
    }
  }
  [self saveFavoriteTitles:filtered];
}

@end
