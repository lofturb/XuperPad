//
//  XPCrypto.m
//

#import "XPCrypto.h"
#import "XPConstants.h"

#import <CommonCrypto/CommonCryptor.h>
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>

static NSString *const XPCryptoErrorDomain = @"XPCrypto";

@implementation XPCrypto

+ (NSData *)tripleDesData:(NSData *)source
                  encrypt:(BOOL)encrypt
                    error:(NSError **)error
{
  if (source.length == 0) {
    if (error) {
      *error = [NSError errorWithDomain:XPCryptoErrorDomain
                                   code:-1
                               userInfo:@{ NSLocalizedDescriptionKey : @"datos vacios" }];
    }
    return nil;
  }

  size_t capacity = source.length + kCCBlockSize3DES;
  NSMutableData *buffer = [NSMutableData dataWithLength:capacity];
  size_t produced = 0;

  CCCryptorStatus status = CCCrypt(encrypt ? kCCEncrypt : kCCDecrypt,
                                   kCCAlgorithm3DES,
                                   kCCOptionECBMode | kCCOptionPKCS7Padding,
                                   XPTripleDesKey(),
                                   kCCKeySize3DES,
                                   NULL,
                                   source.bytes,
                                   source.length,
                                   buffer.mutableBytes,
                                   buffer.length,
                                   &produced);
  if (status != kCCSuccess) {
    if (error) {
      *error = [NSError errorWithDomain:XPCryptoErrorDomain
                                   code:status
                               userInfo:@{ NSLocalizedDescriptionKey :
                                           @"fallo en la operacion 3DES" }];
    }
    return nil;
  }

  buffer.length = produced;
  return [buffer copy];
}

+ (NSString *)encodeRequestBody:(NSString *)plainText error:(NSError **)error
{
  NSData *plain = [plainText dataUsingEncoding:NSUTF8StringEncoding];
  NSData *cipher = [self tripleDesData:plain encrypt:YES error:error];
  if (!cipher) {
    return nil;
  }
  NSString *encoded = [cipher base64EncodedStringWithOptions:0];
  return [self hexStringFromData:[encoded dataUsingEncoding:NSASCIIStringEncoding]];
}

+ (NSString *)decodeResponseBlob:(NSString *)blob error:(NSError **)error
{
  NSData *hexBytes = [self dataFromHexString:blob];
  if (!hexBytes) {
    if (error) {
      *error = [NSError errorWithDomain:XPCryptoErrorDomain
                                   code:-2
                               userInfo:@{ NSLocalizedDescriptionKey : @"respuesta no valida" }];
    }
    return nil;
  }

  NSString *encoded = [[NSString alloc] initWithData:hexBytes encoding:NSASCIIStringEncoding];
  NSData *cipher = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
  if (!cipher) {
    if (error) {
      *error = [NSError errorWithDomain:XPCryptoErrorDomain
                                   code:-3
                               userInfo:@{ NSLocalizedDescriptionKey : @"contenido no valido" }];
    }
    return nil;
  }

  NSData *plain = [self tripleDesData:cipher encrypt:NO error:error];
  if (!plain) {
    return nil;
  }
  return [[NSString alloc] initWithData:plain encoding:NSUTF8StringEncoding];
}

+ (NSString *)md5HexOfData:(NSData *)source
{
  unsigned char digest[CC_MD5_DIGEST_LENGTH];
  CC_MD5(source.bytes, (CC_LONG)source.length, digest);
  NSData *digestData = [NSData dataWithBytes:digest length:CC_MD5_DIGEST_LENGTH];
  return [self hexStringFromData:digestData];
}

+ (NSString *)md5HexOfString:(NSString *)source
{
  return [self md5HexOfData:[source dataUsingEncoding:NSUTF8StringEncoding]];
}

+ (NSString *)hexStringFromData:(NSData *)source
{
  const unsigned char *bytes = source.bytes;
  NSMutableString *result = [NSMutableString stringWithCapacity:source.length * 2];
  for (NSUInteger index = 0; index < source.length; index++) {
    [result appendFormat:@"%02x", bytes[index]];
  }
  return result;
}

+ (NSData *)dataFromHexString:(NSString *)source
{
  NSString *cleaned = [source stringByReplacingOccurrencesOfString:@" " withString:@""];
  if (cleaned.length == 0 || cleaned.length % 2 != 0) {
    return nil;
  }

  NSMutableData *result = [NSMutableData dataWithCapacity:cleaned.length / 2];
  for (NSUInteger index = 0; index < cleaned.length; index += 2) {
    NSString *pair = [cleaned substringWithRange:NSMakeRange(index, 2)];
    unsigned int value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:pair];
    if (![scanner scanHexInt:&value]) {
      return nil;
    }
    unsigned char byte = (unsigned char)value;
    [result appendBytes:&byte length:1];
  }
  return result;
}

+ (NSString *)randomHexStringOfByteCount:(NSUInteger)byteCount
{
  NSMutableData *buffer = [NSMutableData dataWithLength:byteCount];
  if (SecRandomCopyBytes(kSecRandomDefault, byteCount, buffer.mutableBytes) != errSecSuccess) {
    arc4random_buf(buffer.mutableBytes, byteCount);
  }
  return [self hexStringFromData:buffer];
}

+ (NSString *)randomMacAddress
{
  NSMutableString *address = [NSMutableString string];
  for (NSUInteger index = 0; index < 6; index++) {
    if (index > 0) {
      [address appendString:@":"];
    }
    [address appendFormat:@"%02x", (arc4random() & 0xff)];
  }
  return address;
}

@end
