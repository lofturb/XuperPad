//
//  XPSeedPool.h
//  Pool de credenciales anonimas para mantener la sesion viva.
//

#import <Foundation/Foundation.h>

/// Credencial anonima que el portal acepta para crear una sesion.
@interface XPSeedEntry : NSObject

/// Identificador de sesion del dispositivo.
@property (nonatomic, copy) NSString *seed;

/// Identificador de usuario asignado por el portal.
@property (nonatomic, copy) NSString *userIdentifier;

/// Token de sesion asignado por el portal.
@property (nonatomic, copy) NSString *userToken;

/// Momento en segundos epoch cuando caduca la credencial.
@property (nonatomic, assign) NSTimeInterval expiresAt;

/// Momento en segundos epoch cuando se creo la credencial.
@property (nonatomic, assign) NSTimeInterval createdAt;

@end

/// Pool que descarga y administra credenciales anonimas publicas.
@interface XPSeedPool : NSObject

/// Pool compartido por toda la aplicacion.
+ (instancetype)sharedPool;

/// Descarga credenciales nuevas desde las fuentes configuradas.
- (void)refreshWithCompletion:(void (^)(NSUInteger availableCount))completion;

/// Devuelve una credencial vigente, o nil si no hay ninguna.
- (XPSeedEntry *)usableSeed;

/// Marca una credencial como agotada para no volver a usarla.
- (void)markSeedAsExhausted:(NSString *)seed;

/// Numero de credenciales que siguen vigentes.
- (NSUInteger)usableCount;

/// Descripcion del estado del pool para diagnostico.
- (NSDictionary *)statusDescription;

/// Direcciones desde donde se descargan las credenciales.
@property (nonatomic, copy) NSArray *sourceAddresses;

/// Segundos entre dos descargas consecutivas.
@property (nonatomic, assign) NSTimeInterval refreshInterval;

@end
