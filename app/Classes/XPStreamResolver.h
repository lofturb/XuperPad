//
//  XPStreamResolver.h
//  Resuelve la direccion de video y las cabeceras de reproduccion.
//

#import <Foundation/Foundation.h>

/// Se invoca al obtener una direccion de reproduccion.
typedef void (^XPStreamCompletion)(NSDictionary *stream, NSError *error);

/// Resuelve las direcciones de video bajo demanda y en vivo.
@interface XPStreamResolver : NSObject

/// Direccion de video de un capitulo bajo demanda.
+ (void)resolveOnDemandForTitle:(NSString *)contentId
                        seriesId:(NSString *)seriesId
                           title:(NSString *)titleName
                      completion:(XPStreamCompletion)completion;

/// Direccion de video de un canal de television en vivo.
+ (void)resolveLiveForChannel:(NSString *)channelCode
                         title:(NSString *)titleName
                    completion:(XPStreamCompletion)completion;

@end
