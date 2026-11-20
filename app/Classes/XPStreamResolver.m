//
//  XPStreamResolver.m
//

#import "XPStreamResolver.h"
#import "XPConstants.h"
#import "XPCrypto.h"
#import "XPPortalClient.h"
#import "XPPortalParser.h"

static NSString *const XPStreamErrorDomain = @"XPStreamResolver";

@interface XPStreamResolver ()
+ (void)fetchSlbInfoWithPaths:(NSArray *)paths
                    parameters:(NSDictionary *)parameters
                     atIndex:(NSUInteger)index
                    isUsable:(BOOL (^)(NSDictionary *slb))isUsable
                      errors:(NSMutableArray *)errors
                  completion:(void (^)(NSDictionary *slb, NSError *error))completion;
@end

@implementation XPStreamResolver

+ (NSError *)errorWithMessage:(NSString *)message
{
  return [NSError errorWithDomain:XPStreamErrorDomain
                             code:0
                         userInfo:@{ NSLocalizedDescriptionKey : message ?: @"error" }];
}

+ (NSDictionary *)preferredTrackFrom:(NSArray *)tracks
{
  NSDictionary *best = nil;
  NSInteger bestScore = NSIntegerMax;
  for (id item in tracks) {
    if (![item isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSDictionary *track = (NSDictionary *)item;
    NSInteger score = 0;
    NSString *format = track[@"format"];
    if (![format isEqualToString:@"mp4"]) {
      score += 100;
    }
    NSString *codec = track[@"codec"];
    if (![codec isEqualToString:@"h264"]) {
      score += 200;
    }
    NSInteger height = [track[@"height"] integerValue];
    if (height > 1080) {
      score += 80;
    } else if (height > 0 && height < 576) {
      score += 40;
    }
    NSInteger bitrate = [track[@"bitrate"] integerValue];
    if (bitrate > 9000) {
      score += 30;
    }
    if (score < bestScore) {
      bestScore = score;
      best = track;
    }
  }
  return best;
}

+ (void)fetchSlbInfoWithPaths:(NSArray *)paths
                    parameters:(NSDictionary *)parameters
                     isUsable:(BOOL (^)(NSDictionary *slb))isUsable
                   completion:(void (^)(NSDictionary *slb, NSError *error))completion
{
  NSMutableArray *errors = [NSMutableArray array];
  [self fetchSlbInfoWithPaths:paths
                    parameters:parameters
                     atIndex:0
                    isUsable:isUsable
                      errors:errors
                  completion:completion];
}

+ (void)fetchSlbInfoWithPaths:(NSArray *)paths
                    parameters:(NSDictionary *)parameters
                     atIndex:(NSUInteger)index
                    isUsable:(BOOL (^)(NSDictionary *slb))isUsable
                      errors:(NSMutableArray *)errors
                  completion:(void (^)(NSDictionary *slb, NSError *error))completion
{
  if (index >= paths.count) {
    NSError *lastError = errors.lastObject;
    if (completion != nil) {
      completion(nil, lastError ?: [self errorWithMessage:@"el portal no expuso la red de video"]);
    }
    return;
  }

  NSString *path = paths[index];
  [[XPPortalClient sharedClient]
      fetchStreamInformationForPath:path
                         parameters:parameters
                          completion:^(NSDictionary *slb, NSError *error) {
    if (slb != nil && (isUsable == nil || isUsable(slb))) {
      if (completion != nil) {
        completion(slb, nil);
      }
      return;
    }
    if (error != nil) {
      [errors addObject:error];
    }
    [XPStreamResolver fetchSlbInfoWithPaths:paths
                                 parameters:parameters
                                  atIndex:index + 1
                                 isUsable:isUsable
                                   errors:errors
                               completion:completion];
  }];
}

+ (void)resolveOnDemandForTitle:(NSString *)contentId
                        seriesId:(NSString *)seriesId
                           title:(NSString *)titleName
                       completion:(XPStreamCompletion)completion
{
  XPPortalClient *client = [XPPortalClient sharedClient];
  NSDictionary *parameters = @{ @"contentId" : contentId ?: @"",
                                @"seriesContentId" : seriesId ?: @"",
                                @"startTime" : @0,
                                @"type" : @"1",
                                @"columnId" : @0,
                                @"authType" : @"" };

  [client fetchStreamInformationForPath:@"v10/startPlayVOD"
                             parameters:parameters
                              completion:^(NSDictionary *response, NSError *error) {
    if (response == nil) {
      if (completion != nil) {
        completion(nil, error ?: [self errorWithMessage:@"no se pudo iniciar la reproduccion"]);
      }
      return;
    }

    NSArray *tracks = [XPPortalParser tracksFromPlayResponse:response];
    NSLog(@"[XuperPad] vod pistas %lu", (unsigned long)tracks.count);
    if (tracks.count == 0) {
      if (completion != nil) {
        completion(nil, [self errorWithMessage:@"el portal no devolvio pistas de video"]);
      }
      return;
    }

    NSArray *licenses = [XPPortalParser licensesFromPlayResponse:response];
    if (licenses.count == 0) {
      if (completion != nil) {
        completion(nil, [self errorWithMessage:@"el portal no devolvio licencia de reproduccion"]);
      }
      return;
    }

    NSDictionary *track = [self preferredTrackFrom:tracks];
    NSString *license = licenses.firstObject;
    NSString *trackId = track[@"id"];
    NSString *format = [track[@"format"] isEqualToString:@"ts"] ? @"ts" : @"mp4";

    [self fetchSlbInfoWithPaths:@[ @"v14/getSlbInfo", @"v15/getSlbInfo" ]
                     parameters:[self slbParameters]
                      isUsable:^BOOL(NSDictionary *slb) {
                        return [XPPortalParser videoOriginsFromSlbResponse:slb].count > 0;
                      }
                    completion:^(NSDictionary *slb, NSError *slbError) {
      if (slb == nil) {
        if (completion != nil) {
          completion(nil, slbError ?: [self errorWithMessage:@"el portal no expuso la red de video"]);
        }
        return;
      }

      NSArray *origins = [XPPortalParser videoOriginsFromSlbResponse:slb];
      if (origins.count == 0) {
        if (completion != nil) {
          completion(nil, [self errorWithMessage:@"no hay direcciones de video disponibles"]);
        }
        return;
      }

      NSString *suffix = [NSString stringWithFormat:@"/vod/%@_media.%@", trackId, format];
      NSMutableArray *streams = [NSMutableArray array];
      for (id item in origins) {
        if (![item isKindOfClass:[NSDictionary class]]) {
          continue;
        }
        NSDictionary *origin = (NSDictionary *)item;
        NSDictionary *headers = @{ @"Content-Auth" : origin[@"auth"] ?: @"",
                                   @"Content-License" : license ?: @"",
                                   @"User-Agent" : XPCdnUserAgent,
                                   @"App" : XPClientAppId,
                                   @"App-Version" : XPClientAppVersion };
        NSArray *bases = origin[@"bases"];
        if (![bases isKindOfClass:[NSArray class]]) {
          continue;
        }
        for (id base in bases) {
          if (![base isKindOfClass:[NSString class]]) {
            continue;
          }
          NSString *address = [NSString stringWithFormat:@"%@%@", base, suffix];
          [streams addObject:@{ @"url" : address, @"headers" : headers }];
        }
      }

      if (streams.count == 0) {
        if (completion != nil) {
          completion(nil, [self errorWithMessage:@"no hay direcciones de video disponibles"]);
        }
        return;
      }

      NSDictionary *primary = streams.firstObject;
      NSMutableArray *backups = [NSMutableArray array];
      for (NSUInteger index = 1; index < streams.count; index++) {
        [backups addObject:streams[index]];
      }

      NSString *mime = [format isEqualToString:@"ts"] ? @"video/mp2t" : @"video/mp4";
      NSLog(@"[XuperPad] vod direcciones %lu respaldo %lu",
            (unsigned long)streams.count,
            (unsigned long)backups.count);
      if (completion != nil) {
        completion(@{ @"url" : primary[@"url"],
                      @"backupUrls" : backups,
                      @"headers" : primary[@"headers"],
                      @"mime" : mime,
                      @"title" : titleName ?: @"" }, nil);
      }
    }];
  }];
}

+ (NSDictionary *)slbParameters
{
  return @{ @"hasPay" : @"0",
            @"userIdentity" : @"1",
            @"type" : @"merge",
            @"appVer" : XPClientAppVersion,
            @"lang" : @"es",
            @"encMediaSupported" : @1,
            @"liveCodeList" : @[ XPColumnLive ],
            @"appParams" : @"",
            @"reserve1" : XPFixedReserve,
            @"pipFlag" : @"0" };
}

+ (NSString *)signatureForToken:(NSString *)token moment:(long long)moment
{
  NSString *message = [NSString stringWithFormat:
      @"token=%@&sign2_method=sign_o3&instance=0&start_moment=%lld", token, moment];
  NSMutableData *payload = [[message dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
  [payload appendBytes:XPLiveSignatureSalt() length:21];
  return [XPCrypto md5HexOfData:payload];
}

+ (long long)currentMoment
{
  return (long long)[[NSDate date] timeIntervalSince1970];
}

+ (void)resolveLiveForChannel:(NSString *)channelCode
                         title:(NSString *)titleName
                    completion:(XPStreamCompletion)completion
{
  XPPortalClient *client = [XPPortalClient sharedClient];
  NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
  [parameters setObject:channelCode ?: @"" forKey:@"channelCode"];
  [parameters setObject:@"1" forKey:@"type"];

  [client fetchStreamInformationForPath:@"v4/startPlayLive"
                             parameters:parameters
                              completion:^(NSDictionary *response, NSError *error) {
    if (response == nil) {
      if (completion != nil) {
        completion(nil, error ?: [self errorWithMessage:@"no se pudo iniciar el canal"]);
      }
      return;
    }

    NSArray *addressList = response[@"liveAddressList"];
    if (![addressList isKindOfClass:[NSArray class]] || addressList.count == 0) {
      if (completion != nil) {
        completion(nil, [self errorWithMessage:@"el portal no devolvio direccion del canal"]);
      }
      return;
    }

    NSDictionary *entry = nil;
    for (id item in addressList) {
      if (![item isKindOfClass:[NSDictionary class]]) {
        continue;
      }
      NSDictionary *candidate = (NSDictionary *)item;
      NSString *playCode = candidate[@"playCode"];
      NSString *license = candidate[@"license"];
      if (playCode.length > 0 && license.length > 0) {
        entry = candidate;
        break;
      }
    }
    if (entry == nil) {
      entry = addressList.firstObject;
    }

    NSString *playCode = entry[@"playCode"];
    NSString *license = entry[@"license"];
    if (![playCode isKindOfClass:[NSString class]] || playCode.length == 0) {
      playCode = channelCode ?: @"";
    }
    if (![license isKindOfClass:[NSString class]] || license.length == 0) {
      if (completion != nil) {
        completion(nil, [self errorWithMessage:@"el portal no devolvio licencia del canal"]);
      }
      return;
    }

    [self fetchSlbInfoWithPaths:@[ @"v15/getSlbInfo", @"v14/getSlbInfo" ]
                     parameters:[self slbParameters]
                      isUsable:^BOOL(NSDictionary *slb) {
                        return [XPPortalParser liveOriginsFromSlbResponse:slb].count > 0;
                      }
                    completion:^(NSDictionary *slb, NSError *slbError) {
      if (slb == nil) {
        if (completion != nil) {
          completion(nil, slbError ?: [self errorWithMessage:@"el portal no expuso la red en vivo"]);
        }
        return;
      }

      NSArray *origins = [XPPortalParser liveOriginsFromSlbResponse:slb];
      if (origins.count == 0) {
        if (completion != nil) {
          completion(nil, [self errorWithMessage:@"no hay direcciones en vivo disponibles"]);
        }
        return;
      }

      long long moment = [self currentMoment];
      NSMutableArray *streams = [NSMutableArray array];
      for (id item in origins) {
        if (![item isKindOfClass:[NSDictionary class]]) {
          continue;
        }
        NSDictionary *origin = (NSDictionary *)item;
        NSString *host = origin[@"host"];
        NSString *auth = origin[@"auth"];
        if (![host isKindOfClass:[NSString class]] || host.length == 0 ||
            ![auth isKindOfClass:[NSString class]] || auth.length == 0) {
          continue;
        }
        NSString *token = [self tokenFromAuthAddress:auth];
        NSString *signature = [self signatureForToken:token moment:moment];
        NSString *signedAuth = [NSString stringWithFormat:
            @"%@&sign2_method=sign_o3&instance=0&start_moment=%lld&sign2=%@",
            auth, moment, signature];
        NSDictionary *headers = @{ @"Content-Auth" : signedAuth,
                                   @"Content-License" : license,
                                   @"User-Agent" : XPCdnUserAgent,
                                   @"App" : XPClientAppId,
                                   @"App-Version" : XPClientAppVersion,
                                   @"X-Buffer" : @"0" };
        NSString *address = [NSString stringWithFormat:@"http://%@/live/%@.m3u8",
                                                       host, playCode];
        [streams addObject:@{ @"url" : address, @"headers" : headers }];
      }

      if (streams.count == 0) {
        if (completion != nil) {
          completion(nil, [self errorWithMessage:@"no hay direcciones en vivo disponibles"]);
        }
        return;
      }

      NSDictionary *primary = streams.firstObject;
      NSMutableArray *backups = [NSMutableArray array];
      for (NSUInteger index = 1; index < streams.count; index++) {
        [backups addObject:streams[index]];
      }

      if (completion != nil) {
        completion(@{ @"url" : primary[@"url"],
                      @"backupUrls" : backups,
                      @"headers" : primary[@"headers"],
                      @"mime" : @"application/x-mpegurl",
                      @"title" : titleName ?: @"" }, nil);
      }
    }];
  }];
}

+ (NSString *)tokenFromAuthAddress:(NSString *)auth
{
  NSRange start = [auth rangeOfString:@"token="];
  if (start.location == NSNotFound) {
    return @"";
  }
  NSString *rest = [auth substringFromIndex:start.location + 6];
  NSMutableString *token = [NSMutableString string];
  for (NSUInteger index = 0; index < rest.length && token.length < 32; index++) {
    unichar character = [rest characterAtIndex:index];
    BOOL isHex = (character >= '0' && character <= '9') ||
                 (character >= 'a' && character <= 'f') ||
                 (character >= 'A' && character <= 'F');
    if (!isHex) {
      break;
    }
    [token appendFormat:@"%C", character];
  }
  return token;
}

@end
