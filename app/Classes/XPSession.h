//
//  XPSession.h
//  Sesion anonima contra el portal.
//

#import <Foundation/Foundation.h>

/// Se invoca al obtener una sesion valida, siempre en el hilo principal.
typedef void (^XPSessionCompletion)(NSDictionary *sessionInfo, NSError *error);

/// Datos minimos que identifican una sesion activa.
@interface XPSessionState : NSObject

/// Identificador de sesion del dispositivo.
@property (nonatomic, copy) NSString *seed;

/// Identificador de usuario asignado por el portal.
@property (nonatomic, copy) NSString *userIdentifier;

/// Token de sesion asignado por el portal.
@property (nonatomic, copy) NSString *userToken;

/// Momento en segundos epoch cuando caduca la credencial.
@property (nonatomic, assign) NSTimeInterval expiresAt;

/// Indica si la sesion se obtuvo de una credencial anonima publicada.
@property (nonatomic, assign) BOOL fromSharedSeed;

@end

/// Administra la sesion anonima y la renueva cuando caduca.
@interface XPSession : NSObject

/// Sesion compartida por toda la aplicacion.
+ (instancetype)sharedSession;

/// Garantiza que exista una sesion valida y la devuelve.
- (void)ensureSessionWithCompletion:(XPSessionCompletion)completion;

/// Estado actual de la sesion, o nil si no hay ninguna.
- (XPSessionState *)currentState;

/// Descarta la sesion actual para forzar una renovacion.
- (void)invalidate;

@end
