//
//  XPConstants.m
//

#import "XPConstants.h"

NSString *const XPPortalCode = @"masnew";
NSString *const XPClientAppId = @"com.android.msandroid";
NSString *const XPClientAppVersion = @"49902";
NSString *const XPClientPackageVersion = @"2024-09-10 06:25:30_33_13_";
NSString *const XPHttpUserAgent = @"okhttp/3.12.12";
NSString *const XPCdnUserAgent = @"Ranger/4.9.4-17294ac0";
NSString *const XPApiBasePath = @"/api/portalCore/";

NSString *const XPDeviceSalt = @"ntFT65w6itH!lHCPw7D=@qnsFC5adD28";

NSString *const XPFixedReserve = @"583442714b345572434a4d5769637461545a735936413d3d";
NSString *const XPFixedDrmId = @"0iSGEyv2EqiS/nqI/I3hqdu12irw5Q3/uqrWvRFx9bM=";
NSString *const XPFixedMacAddress = @"02:00:00:00:00:00";

NSString *const XPGeoBlockedErrorCode = @"portal100024";
NSString *const XPVersionRejectedErrorCode = @"portal200001";
NSString *const XPCredentialBusyErrorCode = @"aaa100083";
NSString *const XPSessionNotLoggedInErrorCode = @"aaa100028";

NSString *const XPColumnFeatured = @"masnew_featured";
NSString *const XPColumnMovies = @"masnew_movies";
NSString *const XPColumnSeries = @"masnew_series";
NSString *const XPColumnAnime = @"masnew_anime";
NSString *const XPColumnKids = @"masnew_kids";
NSString *const XPColumnFree = @"masnew_free";
NSString *const XPColumnLive = @"masnew_live";

NSArray *XPPortalHosts(void)
{
  static NSArray *hosts = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    hosts = @[
      @"mptec.dhkrxuzcy.com",
      @"ftmrmy.jdfey0cd.com",
      @"fuxok.nguvmqhpk.com",
      @"eajmnp.hcgv1dt8.com",
      @"hinumz.a878kkoyc.com",
      @"krdwvd.swcaw7qx.com",
      @"osuhk.m3x8o50te.com",
      @"oogoy.f30c96w8.com"
    ];
  });
  return hosts;
}

NSString *XPPortalErrorMessage(NSString *returnCode, id rawMessage)
{
  if ([returnCode isEqualToString:XPGeoBlockedErrorCode]) {
    return @"el portal bloquea esta region";
  }
  if ([returnCode isEqualToString:XPVersionRejectedErrorCode]) {
    return @"el portal retiro la version del cliente";
  }
  if ([returnCode isEqualToString:XPCredentialBusyErrorCode]) {
    return @"esa credencial ya esta activa en otro dispositivo";
  }
  if ([returnCode isEqualToString:XPSessionNotLoggedInErrorCode]) {
    return @"la sesion no esta iniciada";
  }
  if ([XPSessionDeadErrorCodes() containsObject:returnCode]) {
    return @"la sesion del portal caduco";
  }
  if ([rawMessage isKindOfClass:[NSString class]] && [rawMessage length] > 0) {
    return rawMessage;
  }
  return @"el portal rechazo la peticion";
}

NSDictionary *XPDeviceParameters(NSString *sn)
{
  return @{ @"sn" : sn ?: @"",
            @"loginType" : @"2",
            @"appLanguage" : @"en",
            @"hardwareInfo" : @"ranchu",
            @"model" : @"sdk_gphone64_arm64",
            @"product" : @"sdk_gphone64_arm64",
            @"cpu" : @"arm64-v8a",
            @"B29" : @"",
            @"reserve1" : XPFixedReserve,
            @"deviceToken" : @"",
            @"drmId" : XPFixedDrmId,
            @"sdkVer" : @33,
            @"apkVersion" : XPClientAppVersion,
            @"sysVersion" : XPClientPackageVersion,
            @"appId" : XPClientAppId };
}

const unsigned char *XPTripleDesKey(void)
{
  static const unsigned char bytes[24] = {
    0xe7, 0xaf, 0x1e, 0xd7, 0xde, 0x1f, 0xfd, 0xdd,
    0x7b, 0xd3, 0xfe, 0x37, 0xeb, 0xdf, 0xfd, 0xe9,
    0xef, 0x3f, 0xe1, 0xae, 0x39, 0xed, 0xfe, 0xb8
  };
  return bytes;
}

const unsigned char *XPLiveSignatureSalt(void)
{
  static const unsigned char bytes[21] = {
    0x73, 0x61, 0x6c, 0x74, 0x33, 0x33, 0x33, 0x33, 0x3d, 0x34,
    0x98, 0x0d, 0x0a, 0x15, 0x32, 0xc9, 0xc3, 0x82, 0x17, 0x08, 0xc0
  };
  return bytes;
}

NSArray *XPSessionDeadErrorCodes(void)
{
  static NSArray *codes = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    codes = @[
      @"aaa100027",
      @"aaa100028",
      @"aaa100080",
      @"aaa100082",
      @"aaa100083"
    ];
  });
  return codes;
}
