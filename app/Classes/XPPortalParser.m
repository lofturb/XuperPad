//
//  XPPortalParser.m
//

#import "XPPortalParser.h"

@implementation XPPortalParser

+ (NSString *)textValue:(id)value
{
  if ([value isKindOfClass:[NSString class]]) {
    return value;
  }
  if ([value isKindOfClass:[NSNumber class]]) {
    return [value stringValue];
  }
  return nil;
}

+ (NSString *)posterFromAsset:(NSDictionary *)asset
{
  NSArray *posterList = asset[@"posterList"];
  if (![posterList isKindOfClass:[NSArray class]]) {
    return nil;
  }
  for (id item in posterList) {
    if (![item isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSDictionary *entry = (NSDictionary *)item;
    NSString *kind = [self textValue:entry[@"fileType"]];
    if ([kind isEqualToString:@"icon"] || [kind isEqualToString:@"poster"]) {
      NSString *address = [self textValue:entry[@"fileUrl"]];
      if (address.length > 0) {
        return address;
      }
    }
  }
  for (id item in posterList) {
    if (![item isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSString *address = [self textValue:((NSDictionary *)item)[@"fileUrl"]];
    if (address.length > 0) {
      return address;
    }
  }
  return nil;
}

+ (NSDictionary *)titleFromAsset:(NSDictionary *)asset
{
  if (![asset isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  NSString *contentId = [self textValue:asset[@"contentId"]];
  if (contentId.length == 0) {
    return nil;
  }
  NSString *name = [self textValue:asset[@"name"]];
  if (name.length == 0) {
    name = contentId;
  }
  NSString *kind = [self textValue:asset[@"programType"]];
  return @{ @"id" : contentId,
            @"name" : name,
            @"poster" : [self posterFromAsset:asset] ?: @"",
            @"summary" : [self textValue:asset[@"description"]] ?: @"",
            @"year" : [self textValue:asset[@"releaseTime"]] ?: @"",
            @"score" : [self textValue:asset[@"score"]] ?: @"",
            @"series" : @([kind isEqualToString:@"2"]),
            @"volumes" : asset[@"volumnCount"] ?: @0 };
}

+ (NSArray *)titlesFromColumnResponse:(NSDictionary *)response
{
  NSMutableArray *result = [NSMutableArray array];
  NSArray *sections = response[@"recommendList"];
  if (![sections isKindOfClass:[NSArray class]]) {
    return result;
  }
  for (id section in sections) {
    if (![section isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSArray *assets = ((NSDictionary *)section)[@"assetList"];
    if (![assets isKindOfClass:[NSArray class]]) {
      continue;
    }
    for (id asset in assets) {
      NSDictionary *title = [self titleFromAsset:asset];
      if (title != nil) {
        [result addObject:title];
      }
    }
  }
  return result;
}

+ (NSArray *)categoriesFromColumnResponse:(NSDictionary *)response
{
  NSMutableArray *result = [NSMutableArray array];
  NSArray *sections = response[@"recommendList"];
  if (![sections isKindOfClass:[NSArray class]]) {
    return result;
  }
  for (id section in sections) {
    if (![section isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSDictionary *entry = (NSDictionary *)section;
    NSString *columnId = [self textValue:entry[@"columnId"]];
    if (columnId.length == 0) {
      continue;
    }
    NSString *name = [self textValue:entry[@"name"]];
    if (name.length == 0) {
      name = [self textValue:entry[@"title"]];
    }
    [result addObject:@{ @"id" : columnId,
                         @"name" : name ?: @"Canal" }];
  }
  return result;
}

+ (NSArray *)titlesFromSearchResponse:(NSDictionary *)response
{
  NSMutableArray *result = [NSMutableArray array];
  NSArray *groups = response[@"searchItemList"];
  if (![groups isKindOfClass:[NSArray class]]) {
    return result;
  }
  for (id group in groups) {
    if (![group isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSArray *items = ((NSDictionary *)group)[@"itemList"];
    if (![items isKindOfClass:[NSArray class]]) {
      continue;
    }
    for (id item in items) {
      NSDictionary *title = [self titleFromAsset:item];
      if (title != nil) {
        [result addObject:title];
      }
    }
  }
  return result;
}

+ (NSArray *)channelsFromLiveResponse:(NSDictionary *)response
{
  NSMutableArray *result = [NSMutableArray array];
  NSArray *channels = response[@"channelList"];
  if (![channels isKindOfClass:[NSArray class]]) {
    return result;
  }
  for (id item in channels) {
    if (![item isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSDictionary *channel = (NSDictionary *)item;
    NSString *code = [self textValue:channel[@"channelCode"]];
    if (code.length == 0) {
      continue;
    }
    NSString *name = [self textValue:channel[@"name"]];
    if (name.length == 0) {
      name = [self textValue:channel[@"alias"]];
    }
    NSString *logo = [self textValue:channel[@"posterUrl"]];
    if (logo.length == 0) {
      NSArray *posterList = channel[@"posterList"];
      if ([posterList isKindOfClass:[NSArray class]] && posterList.count > 0) {
        id first = posterList.firstObject;
        if ([first isKindOfClass:[NSDictionary class]]) {
          logo = [self textValue:((NSDictionary *)first)[@"fileUrl"]];
        }
      }
    }
    [result addObject:@{ @"id" : code,
                         @"name" : name ?: code,
                         @"poster" : logo ?: @"",
                         @"number" : channel[@"channelNumber"] ?: @0 }];
  }
  return result;
}

+ (NSDictionary *)detailFromResponse:(NSDictionary *)response
{
  NSMutableDictionary *detail = [NSMutableDictionary dictionary];
  NSArray *simpleList = response[@"simpleProgramList"];
  if ([simpleList isKindOfClass:[NSArray class]] && simpleList.count > 0) {
    id first = simpleList.firstObject;
    if ([first isKindOfClass:[NSDictionary class]]) {
      NSDictionary *entry = (NSDictionary *)first;
      detail[@"id"] = [self textValue:entry[@"contentId"]] ?: @"";
      detail[@"name"] = [self textValue:entry[@"name"]] ?: @"";
      detail[@"summary"] = [self textValue:entry[@"description"]] ?: @"";
      detail[@"year"] = [self textValue:entry[@"releaseTime"]] ?: @"";
      detail[@"score"] = [self textValue:entry[@"score"]] ?: @"";
      detail[@"poster"] = [self posterFromAsset:entry] ?: @"";
    }
  }

  NSMutableArray *episodes = [NSMutableArray array];
  NSArray *episodeList = response[@"episodeList"];
  if ([episodeList isKindOfClass:[NSArray class]]) {
    for (id item in episodeList) {
      if (![item isKindOfClass:[NSDictionary class]]) {
        continue;
      }
      NSDictionary *entry = (NSDictionary *)item;
      NSString *episodeId = [self textValue:entry[@"contentId"]];
      if (episodeId.length == 0) {
        continue;
      }
      [episodes addObject:@{ @"id" : episodeId,
                             @"name" : [self textValue:entry[@"name"]] ?: episodeId,
                             @"number" : entry[@"episodeNumber"] ?: @0,
                             @"duration" : entry[@"duration"] ?: @0 }];
    }
  }
  detail[@"episodes"] = episodes;

  NSMutableArray *seasons = [NSMutableArray array];
  NSArray *seasonList = response[@"sameSeasonSeriesList"];
  if ([seasonList isKindOfClass:[NSArray class]]) {
    for (id item in seasonList) {
      if (![item isKindOfClass:[NSDictionary class]]) {
        continue;
      }
      NSDictionary *entry = (NSDictionary *)item;
      NSString *seasonId = [self textValue:entry[@"contentId"]];
      if (seasonId.length == 0) {
        continue;
      }
      [seasons addObject:@{ @"id" : seasonId,
                            @"name" : [self textValue:entry[@"name"]] ?: seasonId }];
    }
  }
  detail[@"seasons"] = seasons;
  return detail;
}

+ (NSArray *)tracksFromPlayResponse:(NSDictionary *)response
{
  NSMutableArray *result = [NSMutableArray array];
  NSArray *episodes = response[@"episodeList"];
  if (![episodes isKindOfClass:[NSArray class]]) {
    return result;
  }
  for (id episode in episodes) {
    if (![episode isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSArray *groups = ((NSDictionary *)episode)[@"totalMovieList"];
    if (![groups isKindOfClass:[NSArray class]]) {
      continue;
    }
    for (id group in groups) {
      if (![group isKindOfClass:[NSDictionary class]]) {
        continue;
      }
      NSArray *movies = ((NSDictionary *)group)[@"movieList"];
      if (![movies isKindOfClass:[NSArray class]]) {
        continue;
      }
      for (id movie in movies) {
        if (![movie isKindOfClass:[NSDictionary class]]) {
          continue;
        }
        NSDictionary *entry = (NSDictionary *)movie;
        NSString *contentId = [self textValue:entry[@"contentId"]];
        if (contentId.length == 0) {
          continue;
        }
        NSMutableDictionary *track = [NSMutableDictionary dictionary];
        track[@"id"] = contentId;
        track[@"format"] = [self textValue:entry[@"videoFormat"]] ?: @"mp4";
        track[@"codec"] = [self textValue:entry[@"encodeFormat"]] ?: @"h264";
        track[@"height"] = entry[@"videoHeight"] ?: entry[@"height"] ?: @0;
        track[@"duration"] = entry[@"duration"] ?: @0;
        track[@"size"] = entry[@"fileSize"] ?: @0;
        track[@"bitrate"] = entry[@"videoBitrate"] ?: @0;
        track[@"fps"] = entry[@"frameRate"] ?: @0;
        [result addObject:track];
      }
    }
  }
  return result;
}

+ (NSArray *)licensesFromPlayResponse:(NSDictionary *)response
{
  NSMutableArray *result = [NSMutableArray array];
  NSArray *episodes = response[@"episodeList"];
  if (![episodes isKindOfClass:[NSArray class]]) {
    return result;
  }
  for (id episode in episodes) {
    if (![episode isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSArray *groups = ((NSDictionary *)episode)[@"totalMovieList"];
    if (![groups isKindOfClass:[NSArray class]]) {
      continue;
    }
    for (id group in groups) {
      if (![group isKindOfClass:[NSDictionary class]]) {
        continue;
      }
      NSArray *movies = ((NSDictionary *)group)[@"movieList"];
      if (![movies isKindOfClass:[NSArray class]]) {
        continue;
      }
      for (id movie in movies) {
        if (![movie isKindOfClass:[NSDictionary class]]) {
          continue;
        }
        NSArray *licenseList = ((NSDictionary *)movie)[@"licenseList"];
        if (![licenseList isKindOfClass:[NSArray class]]) {
          continue;
        }
        for (id item in licenseList) {
          if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
          }
          NSString *license = [self textValue:((NSDictionary *)item)[@"license"]];
          if (license.length > 0) {
            [result addObject:license];
          }
        }
      }
    }
  }
  return result;
}

+ (BOOL)isCflAddress:(NSString *)address
{
  if ([address rangeOfString:@"sign_type=cfl"].location != NSNotFound) {
    return YES;
  }
  NSRange separator = [address rangeOfString:@"?"];
  if (separator.location == NSNotFound) {
    return NO;
  }
  NSString *query = [address substringFromIndex:separator.location + 1];
  NSArray *parts = [query componentsSeparatedByString:@"&"];
  for (id part in parts) {
    if ([part isKindOfClass:[NSString class]] && [part isEqualToString:@"sign_type=cfl"]) {
      return YES;
    }
  }
  return NO;
}

+ (BOOL)isFreeAddress:(NSString *)address tag:(NSString *)tag
{
  if ([tag isEqualToString:@"free"]) {
    return YES;
  }
  return [address rangeOfString:@"tag=free"].location != NSNotFound;
}

+ (NSArray *)videoOriginsFromSlbResponse:(NSDictionary *)response
{
  NSArray *cdnList = response[@"cdn_list"];
  if (![cdnList isKindOfClass:[NSArray class]]) {
    return @[];
  }

  NSMutableArray *result = [NSMutableArray array];
  NSMutableArray *freeAddresses = [NSMutableArray array];

  for (id entry in cdnList) {
    if (![entry isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSDictionary *group = (NSDictionary *)entry;
    if (![[self textValue:group[@"tag"]] isEqualToString:@"vod"]) {
      continue;
    }
    NSArray *urlList = group[@"url_list"];
    if (![urlList isKindOfClass:[NSArray class]]) {
      continue;
    }

    NSString *main = [self textValue:group[@"main_addr"]];
    NSString *spare = [self textValue:group[@"spared_addr"]];
    NSMutableArray *bases = [NSMutableArray array];
    if (main.length > 0) {
      [bases addObject:[self normalizedBase:main]];
    }
    if (spare.length > 0) {
      NSString *normalized = [self normalizedBase:spare];
      if (![bases containsObject:normalized]) {
        [bases addObject:normalized];
      }
    }
    if (bases.count == 0) {
      continue;
    }

    for (id item in urlList) {
      if (![item isKindOfClass:[NSDictionary class]]) {
        continue;
      }
      NSDictionary *entryUrl = (NSDictionary *)item;
      NSString *address = [self textValue:entryUrl[@"url"]];
      if (address.length == 0) {
        continue;
      }
      NSString *signType = [self textValue:entryUrl[@"sign_type"]];
      NSString *tag = [self textValue:entryUrl[@"tag"]];
      BOOL signedFree = ([signType isEqualToString:@"cfl"] ||
                         [self isCflAddress:address]) &&
                        [self isFreeAddress:address tag:tag];
      if (signedFree) {
        [result addObject:@{ @"bases" : bases, @"auth" : address }];
        break;
      }
      if ([self isFreeAddress:address tag:tag]) {
        [freeAddresses addObject:@{ @"bases" : bases, @"auth" : address }];
      }
    }
  }

  if (result.count == 0) {
    return freeAddresses;
  }
  return result;
}

+ (NSArray *)liveOriginsFromSlbResponse:(NSDictionary *)response
{
  NSArray *cdnList = response[@"cdn_list"];
  if (![cdnList isKindOfClass:[NSArray class]]) {
    return @[];
  }

  NSMutableArray *result = [NSMutableArray array];
  NSMutableSet *seenHosts = [NSMutableSet set];

  for (NSInteger pass = 0; pass < 2; pass++) {
    for (id entry in cdnList) {
      if (![entry isKindOfClass:[NSDictionary class]]) {
        continue;
      }
      NSDictionary *group = (NSDictionary *)entry;
      if (![[self textValue:group[@"tag"]] isEqualToString:@"live"]) {
        continue;
      }
      NSArray *urlList = group[@"url_list"];
      if (![urlList isKindOfClass:[NSArray class]]) {
        continue;
      }

      NSString *main = [self textValue:group[@"main_addr"]];
      NSString *spare = [self textValue:group[@"spared_addr"]];
      NSMutableArray *hosts = [NSMutableArray array];
      for (id address in @[ main, spare ]) {
        if (![address isKindOfClass:[NSString class]]) {
          continue;
        }
        NSString *host = [self hostFromAddress:address];
        if (host.length > 0 && ![hosts containsObject:host]) {
          [hosts addObject:host];
        }
      }
      if (hosts.count == 0) {
        continue;
      }

      for (id item in urlList) {
        if (![item isKindOfClass:[NSDictionary class]]) {
          continue;
        }
        NSDictionary *entryUrl = (NSDictionary *)item;
        NSString *address = [self textValue:entryUrl[@"url"]];
        if (address.length == 0) {
          continue;
        }
        NSString *signType = [self textValue:entryUrl[@"sign_type"]];
        BOOL usable = (pass == 0)
          ? ([signType isEqualToString:@"cfl"] || [self isCflAddress:address])
          : ([address rangeOfString:@"token="].location != NSNotFound);
        if (!usable) {
          continue;
        }
        for (NSString *host in hosts) {
          if ([seenHosts containsObject:host]) {
            continue;
          }
          [seenHosts addObject:host];
          [result addObject:@{ @"host" : host, @"auth" : address }];
        }
      }
    }
  }
  return result;
}

+ (NSString *)normalizedBase:(NSString *)address
{
  NSString *result = address;
  if ([result hasPrefix:@"http://"]) {
    result = [@"https://" stringByAppendingString:[result substringFromIndex:7]];
  } else if (![result hasPrefix:@"https://"]) {
    result = [@"https://" stringByAppendingString:result];
  }
  while ([result hasSuffix:@"/"]) {
    result = [result substringToIndex:result.length - 1];
  }
  return result;
}

+ (NSString *)hostFromAddress:(NSString *)address
{
  if (address.length == 0) {
    return nil;
  }
  NSString *working = address;
  if ([working hasPrefix:@"https://"]) {
    working = [working substringFromIndex:8];
  } else if ([working hasPrefix:@"http://"]) {
    working = [working substringFromIndex:7];
  }
  NSRange separator = [working rangeOfString:@"/"];
  if (separator.location != NSNotFound) {
    working = [working substringToIndex:separator.location];
  }
  NSRange colon = [working rangeOfString:@":"];
  if (colon.location != NSNotFound) {
    working = [working substringToIndex:colon.location];
  }
  return working;
}

@end
