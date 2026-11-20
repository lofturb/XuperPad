//
//  XPSeedPool.m
//

#import "XPSeedPool.h"
#import "XPTransport.h"

static NSString *const XPSeedFileName = @"xuper-seeds.json";
static NSTimeInterval const XPSeedSafetyMargin = 120;

@implementation XPSeedEntry

- (NSDictionary *)dictionaryRepresentation
{
  return @{ @"sn" : self.seed ?: @"",
            @"userId" : self.userIdentifier ?: @"",
            @"userToken" : self.userToken ?: @"",
            @"mintedAt" : @(self.createdAt),
            @"exp" : @(self.expiresAt) };
}

+ (XPSeedEntry *)entryFromDictionary:(NSDictionary *)source
{
  if (![source isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  NSString *seed = source[@"sn"];
  NSString *userIdentifier = source[@"userId"];
  NSString *userToken = source[@"userToken"];
  if (![seed isKindOfClass:[NSString class]] || seed.length == 0) {
    return nil;
  }
  if (![userIdentifier isKindOfClass:[NSString class]] || userIdentifier.length == 0) {
    return nil;
  }
  if (![userToken isKindOfClass:[NSString class]] || userToken.length == 0) {
    return nil;
  }

  XPSeedEntry *entry = [[XPSeedEntry alloc] init];
  entry.seed = seed;
  entry.userIdentifier = userIdentifier;
  entry.userToken = userToken;
  entry.expiresAt = [source[@"exp"] doubleValue];
  entry.createdAt = [source[@"mintedAt"] doubleValue];
  return entry;
}

@end

@interface XPSeedPool ()
@property (nonatomic, strong) NSMutableArray *entries;
@property (nonatomic, strong) NSMutableArray *exhausted;
@property (nonatomic, assign) BOOL refreshing;
- (void)fetchSeedsAtIndex:(NSUInteger)index
                completion:(void (^)(NSUInteger))completion;
- (void)mergeSeedsFromDictionary:(NSDictionary *)decoded;
@end

@implementation XPSeedPool

+ (instancetype)sharedPool
{
  static XPSeedPool *pool = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    pool = [[XPSeedPool alloc] init];
  });
  return pool;
}

- (instancetype)init
{
  self = [super init];
  if (self) {
    _entries = [NSMutableArray array];
    _exhausted = [NSMutableArray array];
    _refreshInterval = 9 * 60;
    _sourceAddresses = @[
      @"https://raw.githubusercontent.com/cristianco7/XUPER-HYDRA-PORT-WEBOS/seeds/seeds.json",
      @"https://raw.githubusercontent.com/xuper-plugin/kino-plugin-xuper/seeds/seeds.json"
    ];
    [self loadFromDisk];
  }
  return self;
}

- (NSString *)storagePath
{
  NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                       NSUserDomainMask, YES);
  NSString *folder = paths.firstObject ?: NSTemporaryDirectory();
  return [folder stringByAppendingPathComponent:XPSeedFileName];
}

- (void)loadFromDisk
{
  NSData *data = [NSData dataWithContentsOfFile:[self storagePath]];
  if (data == nil) {
    return;
  }
  id decoded = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
  if (![decoded isKindOfClass:[NSDictionary class]]) {
    return;
  }
  NSDictionary *root = (NSDictionary *)decoded;
  NSArray *storedSeeds = root[@"seeds"];
  if ([storedSeeds isKindOfClass:[NSArray class]]) {
    for (id item in storedSeeds) {
      XPSeedEntry *entry = [XPSeedEntry entryFromDictionary:item];
      if (entry != nil) {
        [self.entries addObject:entry];
      }
    }
  }
  NSArray *storedExhausted = root[@"exhausted"];
  if ([storedExhausted isKindOfClass:[NSArray class]]) {
    [self.exhausted addObjectsFromArray:storedExhausted];
  }
}

- (void)saveToDisk
{
  NSMutableArray *storedSeeds = [NSMutableArray array];
  for (XPSeedEntry *entry in self.entries) {
    [storedSeeds addObject:[entry dictionaryRepresentation]];
  }
  NSDictionary *root = @{ @"seeds" : storedSeeds,
                          @"exhausted" : self.exhausted };
  NSData *data = [NSJSONSerialization dataWithJSONObject:root options:0 error:NULL];
  if (data != nil) {
    [data writeToFile:[self storagePath] atomically:YES];
  }
}

- (void)refreshWithCompletion:(void (^)(NSUInteger))completion
{
  if (self.refreshing) {
    if (completion != nil) {
      completion([self usableCount]);
    }
    return;
  }
  self.refreshing = YES;
  [self fetchSeedsAtIndex:0 completion:completion];
}

- (void)fetchSeedsAtIndex:(NSUInteger)index
                completion:(void (^)(NSUInteger))completion
{
  NSArray *addresses = self.sourceAddresses;
  if (index >= addresses.count) {
    self.refreshing = NO;
    if (completion != nil) {
      completion([self usableCount]);
    }
    return;
  }

  NSString *address = addresses[index];
  NSURL *url = [NSURL URLWithString:address];
  if (url == nil) {
    [self fetchSeedsAtIndex:index + 1 completion:completion];
    return;
  }

  [XPTransport getFromAddress:url
                      headers:nil
                      timeout:12
                   completion:^(NSData *data, NSError *error) {
    id decoded = nil;
    if (data != nil && error == nil) {
      decoded = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    }
    if (![decoded isKindOfClass:[NSDictionary class]]) {
      [self fetchSeedsAtIndex:index + 1 completion:completion];
      return;
    }
    [self mergeSeedsFromDictionary:decoded];
    self.refreshing = NO;
    if (completion != nil) {
      completion([self usableCount]);
    }
  }];
}

- (void)mergeSeedsFromDictionary:(NSDictionary *)decoded
{
  id storedSeeds = decoded[@"seeds"];
  if (![storedSeeds isKindOfClass:[NSArray class]]) {
    return;
  }
  for (id item in storedSeeds) {
    XPSeedEntry *entry = [XPSeedEntry entryFromDictionary:item];
    if (entry == nil) {
      continue;
    }
    BOOL alreadyKnown = NO;
    for (XPSeedEntry *known in self.entries) {
      if ([known.seed isEqualToString:entry.seed]) {
        alreadyKnown = YES;
        break;
      }
    }
    if (!alreadyKnown) {
      [self.entries addObject:entry];
    }
  }
  [self saveToDisk];
}

- (XPSeedEntry *)usableSeed
{
  NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
  for (XPSeedEntry *entry in self.entries) {
    if (entry.expiresAt - XPSeedSafetyMargin <= now) {
      continue;
    }
    if ([self.exhausted containsObject:entry.seed]) {
      continue;
    }
    return entry;
  }
  return nil;
}

- (void)markSeedAsExhausted:(NSString *)seed
{
  if (seed.length == 0) {
    return;
  }
  if (![self.exhausted containsObject:seed]) {
    [self.exhausted addObject:seed];
    [self saveToDisk];
  }
}

- (NSUInteger)usableCount
{
  NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
  NSUInteger total = 0;
  for (XPSeedEntry *entry in self.entries) {
    if (entry.expiresAt - XPSeedSafetyMargin <= now) {
      continue;
    }
    if ([self.exhausted containsObject:entry.seed]) {
      continue;
    }
    total++;
  }
  return total;
}

- (NSDictionary *)statusDescription
{
  return @{ @"total" : @(self.entries.count),
            @"usable" : @([self usableCount]),
            @"exhausted" : @(self.exhausted.count) };
}

@end
