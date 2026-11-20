//
//  XPImageCache.m
//

#import "XPImageCache.h"

@interface XPImageCache ()
@property (nonatomic, strong) NSCache *cache;
@property (nonatomic, strong) NSMutableDictionary *pending;
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation XPImageCache

+ (instancetype)sharedCache
{
  static XPImageCache *cache = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    cache = [[XPImageCache alloc] init];
  });
  return cache;
}

- (instancetype)init
{
  self = [super init];
  if (self) {
    _cache = [[NSCache alloc] init];
    _cache.countLimit = 120;
    _pending = [NSMutableDictionary dictionary];
    NSURLSessionConfiguration *configuration =
        [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.requestCachePolicy = NSURLRequestReturnCacheDataElseLoad;
    configuration.timeoutIntervalForRequest = 20;
    _session = [NSURLSession sessionWithConfiguration:configuration];
  }
  return self;
}

- (UIImage *)imageForAddress:(NSString *)address
{
  if (address.length == 0) {
    return nil;
  }
  return [self.cache objectForKey:address];
}

- (void)loadImageForAddress:(NSString *)address
                  completion:(void (^)(UIImage *image))completion
{
  if (completion == nil) {
    return;
  }
  if (address.length == 0) {
    completion(nil);
    return;
  }

  UIImage *cached = [self.cache objectForKey:address];
  if (cached != nil) {
    completion(cached);
    return;
  }

  NSURL *url = [NSURL URLWithString:address];
  if (url == nil) {
    completion(nil);
    return;
  }

  NSMutableArray *handlers = self.pending[address];
  if (handlers == nil) {
    handlers = [NSMutableArray array];
    self.pending[address] = handlers;
  }
  [handlers addObject:[completion copy]];

  if (handlers.count > 1) {
    return;
  }

  __weak XPImageCache *weakSelf = self;
  NSURLSessionDataTask *task =
      [self.session dataTaskWithURL:url
                  completionHandler:^(NSData *data,
                                      NSURLResponse *response,
                                      NSError *error) {
    UIImage *image = nil;
    if (data != nil && error == nil) {
      image = [UIImage imageWithData:data];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      XPImageCache *strongSelf = weakSelf;
      if (strongSelf == nil) {
        completion(image);
        return;
      }
      if (image != nil) {
        [strongSelf.cache setObject:image forKey:address];
      }
      NSArray *waiting = [strongSelf.pending[address] copy];
      [strongSelf.pending removeObjectForKey:address];
      for (id handler in waiting) {
        void (^block)(UIImage *) = handler;
        block(image);
      }
    });
  }];
  [task resume];
}

@end
