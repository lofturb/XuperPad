//
//  XPTransport.h
//  Envio de peticiones HTTP al portal con rotacion de hosts.
//

#import <Foundation/Foundation.h>

/// Se invoca al terminar una peticion, siempre en el hilo principal.
typedef void (^XPTransportCompletion)(NSData *data, NSError *error);

@interface XPTransport : NSObject

/// Envia un POST al portal probando cada host hasta que uno responde.
+ (void)postToPortalHosts:(NSArray *)hosts
                     path:(NSString *)path
                  headers:(NSDictionary *)headers
                     body:(NSData *)body
                  timeout:(NSTimeInterval)timeout
              completion:(XPTransportCompletion)completion;

/// Envia un GET a una direccion cualquiera.
+ (void)getFromAddress:(NSURL *)address
               headers:(NSDictionary *)headers
               timeout:(NSTimeInterval)timeout
            completion:(XPTransportCompletion)completion;

/// Resuelve un nombre de dominio a una direccion IPv4 usando DNS sobre HTTPS.
+ (NSString *)addressForHost:(NSString *)host timeout:(NSTimeInterval)timeout;

/// Vacia la cache de resolucion de nombres.
+ (void)clearNameCache;

@end
