//
//  XPSession.m
//

#import "XPSession.h"
#import "XPConstants.h"
#import "XPCrypto.h"
#import "XPTransport.h"
#import "XPSeedPool.h"

static NSString *const XPSessionErrorDomain = @"XPSession";
static NSString *const XPSessionStoreKey = @"XuperPad.activeSession";
static NSTimeInterval const XPSessionSafetyMargin = 300;
static NSTimeInterval const XPSessionDefaultMaxAge = 21600;
static NSTimeInterval const XPSessionMaxServerAge = 86400;
static NSTimeInterval const XPSessionDefaultHeartbeat = 60;
static NSTimeInterval const XPSessionMinHeartbeat = 30;
static NSTimeInterval const XPSessionMaxHeartbeat = 120;
static NSUInteger const XPSessionMaxActivationAttempts = 2;
static NSUInteger const XPSessionMaxSeedAttempts = 3;

@implementation XPSessionState
@end

@interface XPSession ()
@property (nonatomic, strong) XPSessionState *state;
@property (nonatomic, assign) BOOL working;
@property (nonatomic, strong) NSMutableArray *waiting;
@property (nonatomic, strong) NSTimer *heartbeatTimer;
@property (nonatomic, assign) BOOL heartbeatInFlight;
@property (nonatomic, assign) BOOL restoredFromStore;
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
    [self restoreStoredSession];
  }
  return self;
}

- (XPSessionState *)currentState
{
  return self.state;
}

- (void)invalidate
{
  [self discardCurrentState];
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
  [self discardCurrentState];
}

- (void)restoreStoredSession
{
  NSDictionary *stored = [[NSUserDefaults standardUserDefaults]
                            dictionaryForKey:XPSessionStoreKey];
  if (![stored isKindOfClass:[NSDictionary class]]) {
    return;
  }
  NSString *seed = stored[@"seed"];
  NSString *userIdentifier = stored[@"userId"];
  NSString *userToken = stored[@"userToken"];
  NSString *snToken = stored[@"snToken"];
  if (![seed isKindOfClass:[NSString class]] || seed.length == 0 ||
      ![userIdentifier isKindOfClass:[NSString class]] || userIdentifier.length == 0 ||
      ![userToken isKindOfClass:[NSString class]] || userToken.length == 0 ||
      ![snToken isKindOfClass:[NSString class]] || snToken.length == 0) {
    [self clearStoredSession];
    return;
  }
  NSTimeInterval expiresAt = [stored[@"expiresAt"] doubleValue];
  NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
  if (expiresAt - XPSessionSafetyMargin <= now) {
    NSLog(@"[XuperPad] sesion: la sesion guardada ya habia caducado");
    [self clearStoredSession];
    return;
  }
  XPSessionState *state = [[XPSessionState alloc] init];
  state.seed = seed;
  state.userIdentifier = userIdentifier;
  state.userToken = userToken;
  state.snToken = snToken;
  state.expiresAt = expiresAt;
  state.heartbeatInterval = [stored[@"heartbeatInterval"] doubleValue];
  state.fromSharedSeed = [stored[@"fromSharedSeed"] boolValue];
  self.state = state;
  self.restoredFromStore = YES;
  NSLog(@"[XuperPad] sesion: se restaura la sesion guardada");
}

- (void)persistCurrentState
{
  XPSessionState *state = self.state;
  if (state == nil) {
    [self clearStoredSession];
    return;
  }
  NSDictionary *payload = @{ @"seed" : state.seed ?: @"",
                             @"userId" : state.userIdentifier ?: @"",
                             @"userToken" : state.userToken ?: @"",
                             @"snToken" : state.snToken ?: @"",
                             @"expiresAt" : @(state.expiresAt),
                             @"heartbeatInterval" : @(state.heartbeatInterval),
                             @"fromSharedSeed" : @(state.fromSharedSeed) };
  [[NSUserDefaults standardUserDefaults] setObject:payload forKey:XPSessionStoreKey];
}

- (void)clearStoredSession
{
  [[NSUserDefaults standardUserDefaults] removeObjectForKey:XPSessionStoreKey];
}

- (void)discardCurrentState
{
  [self stopHeartbeat];
  self.state = nil;
  self.restoredFromStore = NO;
  self.heartbeatInFlight = NO;
  [self clearStoredSession];
}

- (void)startHeartbeat
{
  [self stopHeartbeat];
  if (self.state == nil) {
    return;
  }
  NSTimeInterval interval = self.state.heartbeatInterval > 0
                          ? self.state.heartbeatInterval
                          : XPSessionDefaultHeartbeat;
  self.heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:interval
                                                         target:self
                                                       selector:@selector(heartbeatFired:)
                                                       userInfo:nil
                                                        repeats:YES];
  NSLog(@"[XuperPad] sesion: latido cada %.0f s", interval);
}

- (void)stopHeartbeat
{
  [self.heartbeatTimer invalidate];
  self.heartbeatTimer = nil;
}

- (void)heartbeatFired:(NSTimer *)timer
{
  if (self.working || self.heartbeatInFlight) {
    return;
  }
  XPSessionState *state = self.state;
  if (state == nil || state.userToken.length == 0) {
    return;
  }
  if (!state.fromSharedSeed && state.snToken.length == 0) {
    return;
  }
  self.heartbeatInFlight = YES;
  NSString *seed = state.seed;
  NSString *snToken = state.snToken;
  NSDictionary *parameters = [self activationParametersWithSeed:seed snToken:snToken];
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    [self callPortalPath:@"v8/active"
              parameters:parameters
               completion:^(NSDictionary *activation, NSError *error) {
      dispatch_async(dispatch_get_main_queue(), ^{
        self.heartbeatInFlight = NO;
        [self handleHeartbeatResult:activation error:error seed:seed snToken:snToken];
      });
    }];
  });
}

- (void)handleHeartbeatResult:(NSDictionary *)activation
                        error:(NSError *)error
                         seed:(NSString *)seed
                      snToken:(NSString *)snToken
{
  if (activation != nil) {
    XPSessionState *state = self.state;
    if (state == nil) {
      return;
    }
    NSString *userIdentifier = activation[@"userId"];
    NSString *userToken = activation[@"userToken"];
    if ([userIdentifier isKindOfClass:[NSString class]] && userIdentifier.length > 0) {
      state.userIdentifier = userIdentifier;
    }
    if ([userToken isKindOfClass:[NSString class]] && userToken.length > 0) {
      state.userToken = userToken;
    }
    state.snToken = snToken;
    [self applyServerTimingToState:state activation:activation];
    [self persistCurrentState];
    NSTimeInterval remaining = state.expiresAt - [[NSDate date] timeIntervalSince1970];
    NSLog(@"[XuperPad] sesion: latido correcto, vigente %.0f min", remaining / 60.0);
    return;
  }
  NSString *code = error.userInfo[@"portalCode"];
  if ([XPSessionDeadErrorCodes() containsObject:code]) {
    NSLog(@"[XuperPad] sesion: el portal rechazo el latido (%@), se renueva", code);
    [self discardCurrentState];
    [self ensureSessionWithCompletion:nil];
    return;
  }
  NSLog(@"[XuperPad] sesion: el latido no respondio (%@), se reintenta",
        [error localizedDescription] ?: @"sin detalle");
}

- (void)applyServerTimingToState:(XPSessionState *)state
                       activation:(NSDictionary *)activation
{
  NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
  double available = [[activation[@"availableTime"] description] doubleValue];
  if (available <= 0) {
    available = XPSessionDefaultMaxAge;
  }
  if (available > XPSessionMaxServerAge) {
    available = XPSessionMaxServerAge;
  }
  state.expiresAt = now + available;
  double heartbeat = [[activation[@"heartBeatTime"] description] doubleValue];
  if (heartbeat > 0) {
    NSTimeInterval interval = heartbeat / 2.0;
    if (interval < XPSessionMinHeartbeat) {
      interval = XPSessionMinHeartbeat;
    }
    if (interval > XPSessionMaxHeartbeat) {
      interval = XPSessionMaxHeartbeat;
    }
    state.heartbeatInterval = interval;
  } else if (state.heartbeatInterval <= 0) {
    state.heartbeatInterval = XPSessionDefaultHeartbeat;
  }
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
    if (self.restoredFromStore) {
      self.restoredFromStore = NO;
      if (!self.working) {
        self.working = YES;
        [self resumeStoredSessionWithCompletion:^(NSDictionary *resumed, NSError *resumeError) {
          if (resumed != nil) {
            [self notifyWaitingWithState:resumed error:nil];
            return;
          }
          NSString *code = resumeError.userInfo[@"portalCode"];
          if ([XPSessionDeadErrorCodes() containsObject:code]) {
            [self discardCurrentState];
          } else {
            [self startHeartbeat];
            [self notifyWaitingWithState:[self dictionaryFromState:self.state] error:nil];
            return;
          }
          [self createSessionWithCompletion];
        }];
      }
      return;
    }
    [self startHeartbeat];
    [self notifyWaitingWithState:[self dictionaryFromState:self.state] error:nil];
    return;
  }

  if (self.working) {
    return;
  }
  self.working = YES;
  [self createSessionWithCompletion];
}

- (void)createSessionWithCompletion
{
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

- (void)resumeStoredSessionWithCompletion:(void (^)(NSDictionary *, NSError *))completion
{
  XPSessionState *state = self.state;
  if (state == nil) {
    if (completion != nil) {
      completion(nil, [self errorWithMessage:@"no hay sesion guardada"]);
    }
    return;
  }
  NSString *seed = state.seed;
  NSString *snToken = state.snToken;
  NSDictionary *parameters = [self activationParametersWithSeed:seed snToken:snToken];
  [self callPortalPath:@"v8/active"
            parameters:parameters
             completion:^(NSDictionary *activation, NSError *error) {
    NSString *userIdentifier = activation[@"userId"];
    NSString *userToken = activation[@"userToken"];
    if (![userIdentifier isKindOfClass:[NSString class]] || userIdentifier.length == 0 ||
        ![userToken isKindOfClass:[NSString class]] || userToken.length == 0) {
      if (completion != nil) {
        completion(nil, error ?: [self errorWithMessage:@"la sesion guardada no devolvio credenciales"]);
      }
      return;
    }
    XPSessionState *renewed = [[XPSessionState alloc] init];
    renewed.seed = seed;
    renewed.userIdentifier = userIdentifier;
    renewed.userToken = userToken;
    renewed.snToken = snToken;
    renewed.fromSharedSeed = state.fromSharedSeed;
    [self applyServerTimingToState:renewed activation:activation];
    self.state = renewed;
    [self persistCurrentState];
    [self startHeartbeat];
    NSLog(@"[XuperPad] sesion: sesion guardada renovada");
    if (completion != nil) {
      completion([self dictionaryFromState:renewed], nil);
    }
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

- (NSMutableDictionary *)activationParametersWithSeed:(NSString *)seed
                                              snToken:(NSString *)snToken
{
  NSMutableDictionary *parameters =
      [[self deviceParametersWithSeed:seed] mutableCopy];
  if ([snToken isKindOfClass:[NSString class]] && snToken.length > 0) {
    [parameters setObject:snToken forKey:@"snToken"];
  }
  [parameters setObject:@"" forKey:@"authVersion"];
  [parameters setObject:@"" forKey:@"authCode"];
  [parameters setObject:@"" forKey:@"preCode"];
  [parameters setObject:XPFixedMacAddress forKey:@"macAddr"];
  [parameters setObject:@"" forKey:@"reserve1"];
  [parameters setObject:@"4" forKey:@"openNum"];
  [parameters setObject:@"default" forKey:@"channel"];
  [parameters setObject:@"" forKey:@"matadata"];
  [parameters setObject:@"" forKey:@"signdata"];
  return parameters;
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

    NSDictionary *activateParameters =
        [self activationParametersWithSeed:resolvedSeed snToken:snToken];

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
      state.snToken = snToken;
      state.fromSharedSeed = NO;
      [self applyServerTimingToState:state activation:activation];
      self.state = state;
      [self persistCurrentState];
      [self startHeartbeat];
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
    [self persistCurrentState];
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
  NSDictionary *parameters = [self activationParametersWithSeed:entry.seed snToken:@""];

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
    state.fromSharedSeed = YES;
    [self applyServerTimingToState:state activation:activation];
    if (entry.expiresAt > 0 && entry.expiresAt < state.expiresAt) {
      state.expiresAt = entry.expiresAt;
    }
    self.state = state;
    [self persistCurrentState];
    [self startHeartbeat];
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
            @"snToken" : state.snToken ?: @"",
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
