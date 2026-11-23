//
//  XPTransport.m
//

#import "XPTransport.h"
#import "XPConstants.h"

#import <netdb.h>
#import <arpa/inet.h>

static NSString *const XPTransportErrorDomain = @"XPTransport";

static NSMutableDictionary *gXPAddressCache = nil;
static NSTimeInterval const XPAddressCacheLifetime = 6 * 60;

@interface XPTransport ()
+ (void)postToPortalHosts:(NSArray *)hosts
                     path:(NSString *)path
                  headers:(NSDictionary *)headers
                     body:(NSData *)body
                  timeout:(NSTimeInterval)timeout
                  attempt:(NSUInteger)attempt
                lastError:(NSError *)lastError
               completion:(XPTransportCompletion)completion;
@end

@implementation XPTransport

+ (NSMutableDictionary *)addressCache
{
  static NSMutableDictionary *cache = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    cache = [NSMutableDictionary dictionary];
  });
  return cache;
}

+ (BOOL)looksLikeIpv4:(NSString *)text
{
  if (![text isKindOfClass:[NSString class]] || text.length < 7) {
    return NO;
  }
  NSString *pattern = @"^\\d{1,3}(\\.\\d{1,3}){3}$";
  return [text rangeOfString:pattern options:NSRegularExpressionSearch].location != NSNotFound;
}

+ (NSString *)firstAddressFromAnswers:(id)answers
{
  if (![answers isKindOfClass:[NSArray class]]) {
    return nil;
  }
  for (id item in answers) {
    if (![item isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSDictionary *entry = (NSDictionary *)item;
    if ([entry[@"type"] intValue] != 1) {
      continue;
    }
    NSString *candidate = entry[@"data"];
    if ([self looksLikeIpv4:candidate]) {
      return candidate;
    }
  }
  return nil;
}

+ (NSString *)queryNameOverHttps:(NSURL *)address timeout:(NSTimeInterval)timeout
{
  if (!address) {
    return nil;
  }

  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:address];
  request.timeoutInterval = timeout;
  request.HTTPMethod = @"GET";
  request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
  [request setValue:@"application/dns-json" forHTTPHeaderField:@"Accept"];
  [request setValue:@"XuperPad/1.0" forHTTPHeaderField:@"User-Agent"];

  NSURLResponse *response = nil;
  NSError *error = nil;
  NSData *data = [NSURLConnection sendSynchronousRequest:request
                                       returningResponse:&response
                                                   error:&error];
  if (!data || error) {
    return nil;
  }

  id decoded = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
  if (![decoded isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  return [self firstAddressFromAnswers:((NSDictionary *)decoded)[@"Answer"]];
}

+ (NSString *)queryNameWithSystem:(NSString *)host
{
  struct addrinfo hints;
  memset(&hints, 0, sizeof(hints));
  hints.ai_family = AF_INET;
  hints.ai_socktype = SOCK_STREAM;

  struct addrinfo *results = NULL;
  if (getaddrinfo(host.UTF8String, NULL, &hints, &results) != 0 || results == NULL) {
    return nil;
  }

  char text[INET_ADDRSTRLEN] = {0};
  NSString *address = nil;
  struct addrinfo *cursor = results;
  while (cursor != NULL && address == nil) {
    struct sockaddr_in *entry = (struct sockaddr_in *)cursor->ai_addr;
    if (entry != NULL && entry->sin_family == AF_INET &&
        inet_ntop(AF_INET, &entry->sin_addr, text, sizeof(text)) != NULL) {
      address = [NSString stringWithUTF8String:text];
    }
    cursor = cursor->ai_next;
  }
  freeaddrinfo(results);
  return address;
}

+ (NSString *)addressForHost:(NSString *)host timeout:(NSTimeInterval)timeout
{
  if (host.length == 0) {
    return nil;
  }
  if ([self looksLikeIpv4:host]) {
    return host;
  }

  NSMutableDictionary *cache = [self addressCache];
  NSDictionary *entry = cache[host];
  if (entry != nil) {
    double saved = [entry[@"at"] doubleValue];
    if (saved + XPAddressCacheLifetime > [NSDate timeIntervalSinceReferenceDate]) {
      return entry[@"address"];
    }
  }

  NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
      @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"];
  NSString *escaped = [host stringByAddingPercentEncodingWithAllowedCharacters:allowed];
  if (escaped == nil) {
    escaped = host;
  }

  NSArray *templates = @[
    @"https://cloudflare-dns.com/dns-query?type=A&name=%@",
    @"https://dns.google/resolve?type=A&name=%@",
    @"https://dns.quad9.net:5053/dns-query?type=A&name=%@"
  ];

  NSString *address = nil;
  for (NSString *template in templates) {
    NSURL *addressUrl = [NSURL URLWithString:
        [NSString stringWithFormat:template, escaped]];
    address = [self queryNameOverHttps:addressUrl timeout:timeout];
    if (address != nil) {
      break;
    }
  }
  if (address == nil) {
    address = [self queryNameWithSystem:host];
  }
  if (address == nil) {
    return nil;
  }

  cache[host] = @{ @"address" : address,
                   @"at" : @([NSDate timeIntervalSinceReferenceDate]) };
  return address;
}

+ (void)clearNameCache
{
  [[self addressCache] removeAllObjects];
}

+ (NSMutableURLRequest *)requestWithAddress:(NSURL *)address
                                   headers:(NSDictionary *)headers
                                      body:(NSData *)body
                                   timeout:(NSTimeInterval)timeout
{
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:address];
  request.timeoutInterval = timeout;
  request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
  [request setValue:XPHttpUserAgent forHTTPHeaderField:@"User-Agent"];
  for (NSString *name in headers) {
    NSString *value = headers[name];
    if ([value isKindOfClass:[NSString class]] && value.length > 0) {
      [request setValue:value forHTTPHeaderField:name];
    }
  }
  if (body != nil) {
    request.HTTPMethod = @"POST";
    [request setHTTPBody:body];
  } else {
    request.HTTPMethod = @"GET";
  }
  return request;
}

+ (void)postToPortalHosts:(NSArray *)hosts
                     path:(NSString *)path
                  headers:(NSDictionary *)headers
                     body:(NSData *)body
                  timeout:(NSTimeInterval)timeout
              completion:(XPTransportCompletion)completion
{
  if ([NSThread isMainThread]) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      [self postToPortalHosts:hosts
                          path:path
                       headers:headers
                          body:body
                       timeout:timeout
                       attempt:0
                     lastError:nil
                    completion:completion];
    });
    return;
  }
  [self postToPortalHosts:hosts
                      path:path
                   headers:headers
                      body:body
                   timeout:timeout
                   attempt:0
                 lastError:nil
                completion:completion];
}

+ (void)postToPortalHosts:(NSArray *)hosts
                     path:(NSString *)path
                  headers:(NSDictionary *)headers
                     body:(NSData *)body
                  timeout:(NSTimeInterval)timeout
                  attempt:(NSUInteger)attempt
                lastError:(NSError *)lastError
               completion:(XPTransportCompletion)completion
{
  if (attempt >= hosts.count) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (completion != nil) {
        completion(nil, lastError);
      }
    });
    return;
  }

  NSString *host = hosts[attempt];
  NSString *fullPath = [XPApiBasePath stringByAppendingString:path];
  NSURL *address = [NSURL URLWithString:
      [NSString stringWithFormat:@"https://%@%@", host, fullPath]];
  if (address == nil) {
    [self postToPortalHosts:hosts
                        path:path
                     headers:headers
                        body:body
                     timeout:timeout
                     attempt:attempt + 1
                   lastError:lastError
                  completion:completion];
    return;
  }

  NSMutableURLRequest *request = [self requestWithAddress:address
                                                  headers:headers
                                                     body:body
                                                  timeout:timeout];
  NSURLResponse *response = nil;
  NSError *error = nil;
  NSData *data = [NSURLConnection sendSynchronousRequest:request
                                       returningResponse:&response
                                                   error:&error];
  BOOL succeeded = NO;
  if (data != nil && error == nil &&
      [response isKindOfClass:[NSHTTPURLResponse class]]) {
    NSInteger status = [(NSHTTPURLResponse *)response statusCode];
    succeeded = (status >= 200 && status < 300);
    if (!succeeded) {
      error = [NSError errorWithDomain:XPTransportErrorDomain
                                   code:status
                               userInfo:@{ NSLocalizedDescriptionKey :
                                               @"el portal respondio con error" }];
    }
  }

  if (succeeded) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (completion != nil) {
        completion(data, nil);
      }
    });
    return;
  }

  [self postToPortalHosts:hosts
                      path:path
                   headers:headers
                      body:body
                   timeout:timeout
                   attempt:attempt + 1
                 lastError:error
                completion:completion];
}

+ (void)getFromAddress:(NSURL *)address
               headers:(NSDictionary *)headers
               timeout:(NSTimeInterval)timeout
            completion:(XPTransportCompletion)completion
{
  if ([NSThread isMainThread]) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      [self getFromAddress:address headers:headers timeout:timeout completion:completion];
    });
    return;
  }
  if (address == nil) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (completion != nil) {
        completion(nil, [NSError errorWithDomain:XPTransportErrorDomain
                                            code:-1
                                        userInfo:@{ NSLocalizedDescriptionKey :
                                                    @"direccion vacia" }]);
      }
    });
    return;
  }

  NSMutableURLRequest *request = [self requestWithAddress:address
                                                  headers:headers
                                                     body:nil
                                                  timeout:timeout];
  NSURLResponse *response = nil;
  NSError *error = nil;
  NSData *data = [NSURLConnection sendSynchronousRequest:request
                                       returningResponse:&response
                                                   error:&error];
  dispatch_async(dispatch_get_main_queue(), ^{
    if (completion != nil) {
      completion(data, error);
    }
  });
}

@end
