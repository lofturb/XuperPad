//
//  XPPortalClient.m
//

#import "XPPortalClient.h"
#import "XPConstants.h"
#import "XPCrypto.h"
#import "XPTransport.h"
#import "XPSession.h"
#import "XPPortalParser.h"

static NSString *const XPPortalClientErrorDomain = @"XPPortalClient";
static NSTimeInterval const XPPortalTimeout = 18;
static NSUInteger const XPPortalMaxAttempts = 4;

@interface XPPortalClient ()
@property (nonatomic, strong) NSMutableDictionary *cache;
@end

@implementation XPPortalClient

+ (instancetype)sharedClient
{
  static XPPortalClient *client = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    client = [[XPPortalClient alloc] init];
  });
  return client;
}

- (instancetype)init
{
  self = [super init];
  if (self) {
    _cache = [NSMutableDictionary dictionary];
  }
  return self;
}

- (NSMutableDictionary *)bodyWithSessionInfo:(NSDictionary *)sessionInfo
{
  NSMutableDictionary *body =
      [XPDeviceParameters(sessionInfo[@"seed"]) mutableCopy];
  [body setObject:XPPortalCode forKey:@"portalCode"];
  [body setObject:sessionInfo[@"userId"] ?: @"" forKey:@"userId"];
  [body setObject:sessionInfo[@"userToken"] ?: @"" forKey:@"userToken"];
  return body;
}

- (void)callPath:(NSString *)path
      parameters:(NSDictionary *)parameters
       completion:(void (^)(NSDictionary *response, NSError *error))completion
{
  [self callPath:path parameters:parameters attempt:0 completion:completion];
}

- (void)callPath:(NSString *)path
      parameters:(NSDictionary *)parameters
         attempt:(NSUInteger)attempt
       completion:(void (^)(NSDictionary *response, NSError *error))completion
{
  [[XPSession sharedSession] ensureSessionWithCompletion:^(NSDictionary *sessionInfo, NSError *sessionError) {
    if (sessionInfo == nil) {
      if (completion != nil) {
        completion(nil, sessionError);
      }
      return;
    }

    NSMutableDictionary *body = [self bodyWithSessionInfo:sessionInfo];
    [body addEntriesFromDictionary:parameters];

    NSError *encodingError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:body
                                                        options:0
                                                          error:&encodingError];
    if (jsonData == nil) {
      if (completion != nil) {
        completion(nil, encodingError);
      }
      return;
    }

    NSString *jsonText = [[NSString alloc] initWithData:jsonData
                                                encoding:NSUTF8StringEncoding];
    NSError *cryptoError = nil;
    NSString *encodedBody = [XPCrypto encodeRequestBody:jsonText error:&cryptoError];
    if (encodedBody == nil) {
      if (completion != nil) {
        completion(nil, cryptoError);
      }
      return;
    }

    NSDictionary *headers = @{ @"apk" : XPClientAppId,
                               @"apkVer" : @"43404",
                               @"spkgVer" : XPClientPackageVersion,
                               @"Content-Type" : @"application/json;charset=utf-8" };

    [XPTransport postToPortalHosts:XPPortalHosts()
                              path:path
                           headers:headers
                              body:[encodedBody dataUsingEncoding:NSUTF8StringEncoding]
                           timeout:XPPortalTimeout
                         completion:^(NSData *data, NSError *error) {
      if (data == nil) {
        if (completion != nil) {
          completion(nil, error);
        }
        return;
      }

      id decoded = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
      if (![decoded isKindOfClass:[NSDictionary class]]) {
        if (completion != nil) {
          completion(nil, [self errorWithMessage:@"respuesta ilegible del portal"]);
        }
        return;
      }

      NSDictionary *envelope = (NSDictionary *)decoded;
      NSString *returnCode = [envelope[@"returnCode"] description];
      NSLog(@"[XuperPad] portal %@ returnCode %@ intento %lu",
            path, returnCode, (unsigned long)(attempt + 1));
      if (![returnCode isEqualToString:@"0"]) {
        NSString *message = XPPortalErrorMessage(returnCode, envelope[@"errorMessage"]);
        BOOL canRetry = (attempt + 1) < XPPortalMaxAttempts;
        if (canRetry && [XPSessionDeadErrorCodes() containsObject:returnCode]) {
          NSLog(@"[XuperPad] portal %@ sesion muerta (%@), se renueva y se reintenta",
                path, returnCode);
          [[XPSession sharedSession] invalidateSharedSeed];
          [self callPath:path parameters:parameters attempt:attempt + 1 completion:completion];
          return;
        }
        if (canRetry && [returnCode isEqualToString:XPGeoBlockedErrorCode]) {
          NSLog(@"[XuperPad] portal %@ bloqueo geografico (%@), se reintenta",
                path, returnCode);
          [[XPSession sharedSession] invalidateSharedSeed];
          [self callPath:path parameters:parameters attempt:attempt + 1 completion:completion];
          return;
        }
        if (completion != nil) {
          completion(nil, [self errorWithMessage:message code:returnCode]);
        }
        return;
      }

      id payload = envelope[@"data"];
      NSDictionary *result = nil;
      if ([payload isKindOfClass:[NSDictionary class]]) {
        result = (NSDictionary *)payload;
      } else if ([payload isKindOfClass:[NSString class]]) {
        NSError *decodeError = nil;
        NSString *plain = [XPCrypto decodeResponseBlob:(NSString *)payload
                                                  error:&decodeError];
        if (plain != nil) {
          id inner = [NSJSONSerialization JSONObjectWithData:
                        [plain dataUsingEncoding:NSUTF8StringEncoding]
                                                     options:0
                                                       error:NULL];
          if ([inner isKindOfClass:[NSDictionary class]]) {
            result = (NSDictionary *)inner;
          }
        }
      }

      if (result == nil) {
        if (completion != nil) {
          completion(nil, [self errorWithMessage:@"el portal no devolvio datos"]);
        }
        return;
      }

      if (completion != nil) {
        completion(result, nil);
      }
    }];
  }];
}

- (NSError *)errorWithMessage:(NSString *)message
{
  return [self errorWithMessage:message code:@"unknown"];
}

- (NSError *)errorWithMessage:(NSString *)message code:(NSString *)code
{
  return [NSError errorWithDomain:XPPortalClientErrorDomain
                             code:0
                         userInfo:@{ NSLocalizedDescriptionKey : message ?: @"error",
                                     @"portalCode" : code ?: @"unknown" }];
}

- (void)fetchSectionsForColumn:(NSString *)columnCode
                           page:(NSUInteger)page
                     completion:(void (^)(NSArray *sections, NSError *error))completion
{
  NSDictionary *parameters = @{ @"columnCode" : columnCode ?: XPColumnFeatured,
                                @"pageNum" : @(page),
                                @"pageSize" : @60,
                                @"version" : @"" };
  [self callPath:@"getNextColumns"
       parameters:parameters
        completion:^(NSDictionary *response, NSError *error) {
    if (response == nil) {
      if (completion != nil) {
        completion(nil, error);
      }
      return;
    }
    if (completion != nil) {
      completion([XPPortalParser sectionsFromColumnResponse:response], nil);
    }
  }];
}

- (void)fetchTitlesForColumn:(NSString *)columnCode
                        page:(NSUInteger)page
                  completion:(XPTitleListCompletion)completion
{
  [self fetchSectionsForColumn:columnCode
                           page:page
                     completion:^(NSArray *sections, NSError *error) {
    if (sections == nil) {
      if (completion != nil) {
        completion(nil, error);
      }
      return;
    }
    NSMutableArray *titles = [NSMutableArray array];
    for (id section in sections) {
      if (![section isKindOfClass:[NSDictionary class]]) {
        continue;
      }
      NSArray *items = ((NSDictionary *)section)[@"items"];
      if ([items isKindOfClass:[NSArray class]]) {
        [titles addObjectsFromArray:items];
      }
    }
    if (completion != nil) {
      completion(titles, nil);
    }
  }];
}

- (void)searchTitles:(NSString *)text
                 page:(NSUInteger)page
           completion:(XPTitleListCompletion)completion
{
  NSDictionary *parameters = @{ @"value" : text ?: @"",
                                @"type" : @"1",
                                @"columnId" : @"",
                                @"filter" : @"",
                                @"pageNum" : @(page),
                                @"pageSize" : @50 };
  [self callPath:@"v3/searchByName"
       parameters:parameters
        completion:^(NSDictionary *response, NSError *error) {
    if (response == nil) {
      if (completion != nil) {
        completion(nil, error);
      }
      return;
    }
    if (completion != nil) {
      completion([XPPortalParser titlesFromSearchResponse:response], nil);
    }
  }];
}

- (void)fetchDetailForTitle:(NSString *)contentId
                     isSeries:(BOOL)isSeries
                   completion:(XPTitleDetailCompletion)completion
{
  NSString *primaryType = isSeries ? @"0" : @"1";
  NSString *alternateType = isSeries ? @"1" : @"0";
  [self fetchDetailForTitle:contentId
                        type:primaryType
                 alternateType:alternateType
                       retried:NO
                   completion:completion];
}

- (void)fetchDetailForTitle:(NSString *)contentId
                        type:(NSString *)callType
               alternateType:(NSString *)alternateType
                     retried:(BOOL)retried
                 completion:(XPTitleDetailCompletion)completion
{
  NSDictionary *parameters = @{ @"contentId" : contentId ?: @"",
                                @"type" : callType ?: @"1",
                                @"sortType" : @"0",
                                @"language" : @"en",
                                @"macAddr" : XPFixedMacAddress };
  [self callPath:@"v4/getItemData"
       parameters:parameters
        completion:^(NSDictionary *response, NSError *error) {
    if (response == nil) {
      if (!retried && alternateType.length > 0) {
        [self fetchDetailForTitle:contentId
                              type:alternateType
                     alternateType:nil
                           retried:YES
                       completion:completion];
        return;
      }
      if (completion != nil) {
        completion(nil, error);
      }
      return;
    }
    NSDictionary *detail = [XPPortalParser detailFromResponse:response];
    if (detail == nil) {
      if (completion != nil) {
        completion(nil, [self errorWithMessage:@"el portal no devolvio el detalle"]);
      }
      return;
    }
    if (completion != nil) {
      completion(detail, nil);
    }
  }];
}

- (void)fetchLiveCategoriesWithCompletion:(XPTitleListCompletion)completion
{
  NSDictionary *parameters = @{ @"columnCode" : XPColumnLive,
                                @"pageNum" : @1,
                                @"pageSize" : @200,
                                @"version" : @"" };
  [self callPath:@"getNextColumns"
       parameters:parameters
        completion:^(NSDictionary *response, NSError *error) {
    if (response == nil) {
      if (completion != nil) {
        completion(nil, error);
      }
      return;
    }
    if (completion != nil) {
      completion([XPPortalParser categoriesFromColumnResponse:response], nil);
    }
  }];
}

- (void)fetchLiveChannelsForColumn:(NSString *)columnIdentifier
                               page:(NSUInteger)page
                         completion:(XPTitleListCompletion)completion
{
  NSDictionary *parameters = @{ @"columnId" : columnIdentifier ?: @"76182",
                                @"dataVersion" : @"",
                                @"pageSize" : @60,
                                @"pageNum" : @(page),
                                @"expireTimeStr" : @"" };
  [self callPath:@"v6/getLiveData"
       parameters:parameters
        completion:^(NSDictionary *response, NSError *error) {
    if (response == nil) {
      if (completion != nil) {
        completion(nil, error);
      }
      return;
    }
    if (completion != nil) {
      completion([XPPortalParser channelsFromLiveResponse:response], nil);
    }
  }];
}

- (void)fetchStreamInformationForPath:(NSString *)path
                            parameters:(NSDictionary *)parameters
                             completion:(void (^)(NSDictionary *, NSError *))completion
{
  [self callPath:path parameters:parameters completion:completion];
}

@end
