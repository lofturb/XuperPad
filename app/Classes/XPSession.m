//
//  XPSession.m
//

#import "XPSession.h"
#import "XPConstants.h"
#import "XPCrypto.h"
#import "XPTransport.h"
#import "XPSeedPool.h"

static NSString *const XPSessionErrorDomain = @"XPSession";
static NSTimeInterval const XPSessionSafetyMargin = 300;
static NSTimeInterval const XPSessionMaxAge = 21600;
static NSUInteger const XPSessionMaxActivationAttempts = 2;
static NSUInteger const XPSessionMaxSeedAttempts = 3;

@implementation XPSessionState
@end

@interface XPSession ()
@property (nonatomic, strong) XPSessionState *state;
@property (nonatomic, assign) BOOL working;
@property (nonatomic, strong) NSMutableArray *waiting;
@end

@implementation XPSession

+ (instancetype)sharedSession
{
  static XPSession *session = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    session = [[XPSession alloc] init];
  });
  return session;
}

- (instancetype)init
{
  self = [super init];
  if (self) {
    _waiting = [NSMutableArray array];
  }
  return self;
}

- (XPSessionState *)currentState
{
  return self.state;
}

- (void)invalidate
{
  self.state = nil;
}

- (void)invalidateSharedSeed
{
  if (self.state != nil && self.state.fromSharedSeed) {
    NSString *seed = self.state.seed;
    if (seed.length > 0) {
      [[XPSeedPool sharedPool] markSeedAsExhausted:seed];
      NSLog(@"[XuperPad] sesion: credencial compartida descartada");
    }
  }
  self.state = nil;
}

- (NSDictionary *)deviceParametersWithSeed:(NSString *)seed
{
  return XPDeviceParameters(seed);
}

- (void)ensureSessionWithCompletion:(XPSessionCompletion)completion
{
  if (completion != nil) {
    [self.waiting addObject:[completion copy]];
  }

  NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
  if (self.state != nil &&
      self.state.userToken.length > 0 &&
      self.state.expiresAt - XPSessionSafetyMargin > now) {
    [self notifyWaitingWithState:[self dictionaryFromState:self.state] error:nil];
    return;
  }

  if (self.working) {
    return;
  }
  self.working = YES;

  /* El port de referencia activa el dispositivo contra el portal y solo
     recurre a una credencial publicada cuando la activacion real falla por
     red o por bloqueo regional. Las credenciales publicadas estan atadas a
     la IP que las acuño, asi que adoptarlas primero deja al portal
     respondiendo aaa100083 (cuenta abierta en otro dispositivo). */
  [self activateFreshSessionWithAttempt:0 completion:^(NSDictionary *fresh, NSError *freshError) {
    if (fresh != nil) {
      [self notifyWaitingWithState:fresh error:nil];
      return;
    }
    NSLog(@"[XuperPad] sesion: activacion real no disponible (%@), se prueban credenciales publicadas",
          [freshError localizedDescription] ?: @"sin detalle");
    [self adoptSharedSeedWithCompletion:^(NSDictionary *seedResult, NSError *seedError) {
      if (seedResult != nil) {
        [self notifyWaitingWithState:seedResult error:nil];
        return;
      }
      [self notifyWaitingWithState:nil error:(freshError ?: seedError)];
    }];
  }];
}

- (void)activateFreshSessionWithAttempt:(NSUInteger)attempt
                              completion:(void (^)(NSDictionary *, NSError *))completion
{
  [self createFreshSessionWithCompletion:^(NSDictionary *result, NSError *error) {
    if (result != nil) {
      if (completion != nil) {
        completion(result, nil);
      }
      return;
    }
    NSString *code = error.userInfo[@"portalCode"];
    BOOL networkFailure = (code == nil || [code isEqualToString:@"unknown"]);
    if (networkFailure && attempt + 1 < XPSessionMaxActivationAttempts) {
      NSLog(@"[XuperPad] sesion: activacion real fallo por red (%@), se reintenta",
            [error localizedDescription] ?: @"sin detalle");
      [self activateFreshSessionWithAttempt:attempt + 1 completion:completion];
      return;
    }
    if (completion != nil) {
      completion(nil, error);
    }
  }];
}

- (void)notifyWaitingWithState:(NSDictionary *)state error:(NSError *)error
{
  self.working = NO;
  NSArray *callbacks = [self.waiting copy];
  [self.waiting removeAllObjects];
  for (XPSessionCompletion callback in callbacks) {
    callback(state, error);
  }
}

- (NSString *)randomMacAddress
{
  NSString *raw = [XPCrypto randomHexStringOfByteCount:6];
  NSMutableArray *pieces = [NSMutableArray array];
  for (NSUInteger index = 0; index + 1 < raw.length; index += 2) {
    [pieces addObject:[raw substringWithRange:NSMakeRange(index, 2)]];
  }
  return [pieces componentsJoinedByString:@":"];
}

- (NSDictionary *)buildFingerprint
{
  NSMutableDictionary *fingerprint = [NSMutableDictionary dictionary];
  [fingerprint setObject:@"goldfish_arm64" forKey:@"board"];
  [fingerprint setObject:@"google" forKey:@"brand"];
  [fingerprint setObject:@"arm64-v8a" forKey:@"cpuAbi"];
  [fingerprint setObject:@"emu64a" forKey:@"device"];
  [fingerprint setObject:@"8GB" forKey:@"diskInfo"];
  [fingerprint setObject:@"sdk_gphone64_arm64" forKey:@"display"];
  [fingerprint setObject:@"google/sdk_gphone64_arm64/emu64a:14/UE1A.230829.036/11228894:user/release-keys"
                  forKey:@"fingerprint"];
  [fingerprint setObject:@"ranchu" forKey:@"hardware"];
  [fingerprint setObject:@"abfarm" forKey:@"host"];
  [fingerprint setObject:@"Google" forKey:@"manufacturer"];
  [fingerprint setObject:@"4GB" forKey:@"ramSize"];
  [fingerprint setObject:@"8GB" forKey:@"romSize"];
  [fingerprint setObject:@"release-keys" forKey:@"tags"];
  [fingerprint setObject:@"" forKey:@"verId"];
  [fingerprint setObject:[XPCrypto md5HexOfString:
                          [XPCrypto randomHexStringOfByteCount:8]]
                  forKey:@"deviceId"];
  [fingerprint setObject:@"phone" forKey:@"deviceType"];
  [fingerprint setObject:@"9" forKey:@"osVersion"];
  [fingerprint setObject:@"1" forKey:@"osBuild"];
  [fingerprint setObject:@"10001" forKey:@"channelId"];
  [fingerprint setObject:[XPCrypto randomHexStringOfByteCount:8] forKey:@"androidId"];
  [fingerprint setObject:[XPCrypto randomHexStringOfByteCount:8] forKey:@"cpuId"];
  [fingerprint setObject:[XPCrypto randomHexStringOfByteCount:8] forKey:@"serialNumber"];
  [fingerprint setObject:@"9" forKey:@"androidVersion"];
  [fingerprint setObject:@"unknown" forKey:@"phoneType"];
  [fingerprint setObject:@"sdk_gphone64_arm64" forKey:@"phoneModel"];
  [fingerprint setObject:@"1.0" forKey:@"protocolVersion"];
  [fingerprint setObject:@"arm64-v8a" forKey:@"cpuType"];
  [fingerprint setObject:XPClientAppVersion forKey:@"appVersion"];
  [fingerprint setObject:XPClientPackageVersion forKey:@"systemVersion"];
  [fingerprint setObject:[self randomMacAddress] forKey:@"etheMac"];
  [fingerprint setObject:[self randomMacAddress] forKey:@"gatewayMac"];
  [fingerprint setObject:[self randomMacAddress] forKey:@"wifiMac"];
  return fingerprint;
}

- (void)createFreshSessionWithCompletion:(void (^)(NSDictionary *, NSError *))completion
{
  NSMutableDictionary *parameters = [[self deviceParametersWithSeed:@""] mutableCopy];
  [parameters addEntriesFromDictionary:[self buildFingerprint]];

  [self callPortalPath:@"v3/snToken"
            parameters:parameters
             completion:^(NSDictionary *response, NSError *error) {
    NSString *snToken = response[@"snToken"];
    if (![snToken isKindOfClass:[NSString class]] || snToken.length == 0) {
      if (completion != nil) {
        completion(nil, error ?: [self errorWithMessage:@"no se obtuvo el token de sesion"]);
      }
      return;
    }

    NSString *resolvedSeed = response[@"sn"];
    if (![resolvedSeed isKindOfClass:[NSString class]] || resolvedSeed.length == 0) {
      resolvedSeed = [XPCrypto md5HexOfString:
                        [snToken stringByAppendingString:XPDeviceSalt]];
    }

    NSMutableDictionary *activateParameters =
        [[self deviceParametersWithSeed:resolvedSeed] mutableCopy];
    [activateParameters setObject:snToken forKey:@"snToken"];
    [activateParameters setObject:@"" forKey:@"authVersion"];
    [activateParameters setObject:@"" forKey:@"authCode"];
    [activateParameters setObject:@"" forKey:@"preCode"];
    [activateParameters setObject:XPFixedMacAddress forKey:@"macAddr"];
    [activateParameters setObject:@"" forKey:@"reserve1"];
    [activateParameters setObject:@"4" forKey:@"openNum"];
    [activateParameters setObject:@"default" forKey:@"channel"];
    [activateParameters setObject:@"" forKey:@"matadata"];
    [activateParameters setObject:@"" forKey:@"signdata"];

    [self callPortalPath:@"v8/active"
              parameters:activateParameters
               completion:^(NSDictionary *activation, NSError *activationError) {
      NSString *userIdentifier = activation[@"userId"];
      NSString *userToken = activation[@"userToken"];
      if (![userIdentifier isKindOfClass:[NSString class]] || userIdentifier.length == 0 ||
          ![userToken isKindOfClass:[NSString class]] || userToken.length == 0) {
        if (completion != nil) {
          completion(nil, activationError ?: [self errorWithMessage:@"no se activo la sesion"]);
        }
        return;
      }

      XPSessionState *state = [[XPSessionState alloc] init];
      state.seed = resolvedSeed;
      state.userIdentifier = userIdentifier;
      state.userToken = userToken;
      state.expiresAt = [[NSDate date] timeIntervalSince1970] + XPSessionMaxAge;
      state.fromSharedSeed = NO;
      self.state = state;
      NSLog(@"[XuperPad] sesion: creada desde cero");
      if (completion != nil) {
        completion([self dictionaryFromState:state], nil);
      }
    }];
  }];
}

- (void)adoptSharedSeedWithCompletion:(void (^)(NSDictionary *, NSError *))completion
{
  XPSeedPool *pool = [XPSeedPool sharedPool];
  [pool refreshWithCompletion:^(NSUInteger availableCount) {
    [self adoptSeedWithAttempt:0 completion:completion];
  }];
}

- (void)adoptSeedWithAttempt:(NSUInteger)attempt
                   completion:(void (^)(NSDictionary *, NSError *))completion
{
  XPSeedPool *pool = [XPSeedPool sharedPool];
  XPSeedEntry *entry = [pool usableSeed];
  if (entry == nil) {
    if (completion != nil) {
      completion(nil, [self errorWithMessage:@"no hay credenciales anonimas disponibles"]);
    }
    return;
  }

  if (entry.userIdentifier.length > 0 && entry.userToken.length > 0) {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    XPSessionState *state = [[XPSessionState alloc] init];
    state.seed = entry.seed;
    state.userIdentifier = entry.userIdentifier;
    state.userToken = entry.userToken;
    state.expiresAt = entry.expiresAt > now + 600 ? entry.expiresAt : now + 600;
    state.fromSharedSeed = YES;
    self.state = state;
    NSLog(@"[XuperPad] sesion: credencial compartida adoptada");
    if (completion != nil) {
      completion([self dictionaryFromState:state], nil);
    }
    return;
  }

  [self activateSeed:entry completion:^(NSDictionary *result, NSError *error) {
    if (result != nil) {
      if (completion != nil) {
        completion(result, nil);
      }
      return;
    }
    if (attempt + 1 < XPSessionMaxSeedAttempts) {
      NSLog(@"[XuperPad] sesion: credencial no activable, se prueba otra");
      [self adoptSeedWithAttempt:attempt + 1 completion:completion];
      return;
    }
    if (completion != nil) {
      completion(nil, error);
    }
  }];
}

- (void)activateSeed:(XPSeedEntry *)entry
           completion:(void (^)(NSDictionary *, NSError *))completion
{
  XPSeedPool *pool = [XPSeedPool sharedPool];
  NSMutableDictionary *parameters =
      [[self deviceParametersWithSeed:entry.seed] mutableCopy];
  [parameters setObject:@"" forKey:@"authVersion"];
  [parameters setObject:@"" forKey:@"authCode"];
  [parameters setObject:@"" forKey:@"preCode"];
  [parameters setObject:XPFixedMacAddress forKey:@"macAddr"];
  [parameters setObject:@"" forKey:@"reserve1"];
  [parameters setObject:@4 forKey:@"openNum"];
  [parameters setObject:@"default" forKey:@"channel"];
  [parameters setObject:@"" forKey:@"matadata"];
  [parameters setObject:@"" forKey:@"signdata"];

  [self callPortalPath:@"v8/active"
            parameters:parameters
             completion:^(NSDictionary *activation, NSError *activationError) {
    NSString *userIdentifier = activation[@"userId"];
    NSString *userToken = activation[@"userToken"];
    if (![userIdentifier isKindOfClass:[NSString class]] || userIdentifier.length == 0 ||
        ![userToken isKindOfClass:[NSString class]] || userToken.length == 0) {
      [pool markSeedAsExhausted:entry.seed];
      if (completion != nil) {
        completion(nil, activationError ?: [self errorWithMessage:@"no se pudo reutilizar la credencial"]);
      }
      return;
    }

    XPSessionState *state = [[XPSessionState alloc] init];
    state.seed = entry.seed;
    state.userIdentifier = userIdentifier;
    state.userToken = userToken;
    state.expiresAt = entry.expiresAt;
    state.fromSharedSeed = YES;
    self.state = state;
    if (completion != nil) {
      completion([self dictionaryFromState:state], nil);
    }
  }];
}

- (NSDictionary *)dictionaryFromState:(XPSessionState *)state
{
  return @{ @"seed" : state.seed ?: @"",
            @"userId" : state.userIdentifier ?: @"",
            @"userToken" : state.userToken ?: @"",
            @"expiresAt" : @(state.expiresAt),
            @"fromSharedSeed" : @(state.fromSharedSeed) };
}

- (void)callPortalPath:(NSString *)path
             parameters:(NSDictionary *)parameters
              completion:(void (^)(NSDictionary *, NSError *))completion
{
  NSMutableDictionary *body = [parameters mutableCopy];

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
                         timeout:15
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

    NSDictionary *response = (NSDictionary *)decoded;
    NSString *returnCode = [response[@"returnCode"] description];
    if (![returnCode isEqualToString:@"0"]) {
      NSString *message = XPPortalErrorMessage(returnCode, response[@"errorMessage"]);
      if (completion != nil) {
        completion(nil, [self errorWithMessage:message code:returnCode]);
      }
      return;
    }

    id payload = response[@"data"];
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
}

- (NSError *)errorWithMessage:(NSString *)message
{
  return [self errorWithMessage:message code:@"unknown"];
}

- (NSError *)errorWithMessage:(NSString *)message code:(NSString *)code
{
  return [NSError errorWithDomain:XPSessionErrorDomain
                             code:0
                         userInfo:@{ NSLocalizedDescriptionKey : message ?: @"error",
                                     @"portalCode" : code ?: @"unknown" }];
}

@end
