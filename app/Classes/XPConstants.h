//
//  XPConstants.h
//  Constantes del protocolo del portal XuperTV.
//

#import <Foundation/Foundation.h>

/// Codigo de portal que se envia en cada peticion.
extern NSString *const XPPortalCode;

/// Identificador de la aplicacion cliente que declara el portal.
extern NSString *const XPClientAppId;

/// Version de aplicacion que declara el portal.
extern NSString *const XPClientAppVersion;

/// Version de paquete que declara el portal.
extern NSString *const XPClientPackageVersion;

/// Agente de usuario HTTP del cliente.
extern NSString *const XPHttpUserAgent;

/// Agente de usuario HTTP del CDN de video.
extern NSString *const XPCdnUserAgent;

/// Ruta base de la API del portal.
extern NSString *const XPApiBasePath;

/// Hosts del portal, en orden de preferencia.
extern NSArray *XPPortalHosts(void);

/// Parametros de dispositivo que el portal exige en cada peticion.
extern NSDictionary *XPDeviceParameters(NSString *sn);

/// Clave de 3DES del protocolo (24 bytes, 3 claves).
extern const unsigned char *XPTripleDesKey(void);

/// Sal de texto para derivar el identificador de dispositivo.
extern NSString *const XPDeviceSalt;

/// Sal binaria de la firma O3 del CDN en vivo (21 bytes).
extern const unsigned char *XPLiveSignatureSalt(void);

/// Valores fijos de dispositivo que el portal espera.
extern NSString *const XPFixedReserve;
extern NSString *const XPFixedDrmId;
extern NSString *const XPFixedMacAddress;

/// Codigos de error del portal que invalidan la sesion actual.
extern NSArray *XPSessionDeadErrorCodes(void);

/// Codigo de error del portal que indica bloqueo geografico.
extern NSString *const XPGeoBlockedErrorCode;

/// Traduce el codigo y el mensaje del portal a un texto en castellano.
extern NSString *XPPortalErrorMessage(NSString *returnCode, id rawMessage);

/// Columnas de catalogo disponibles.
extern NSString *const XPColumnFeatured;
extern NSString *const XPColumnMovies;
extern NSString *const XPColumnSeries;
extern NSString *const XPColumnAnime;
extern NSString *const XPColumnKids;
extern NSString *const XPColumnFree;
extern NSString *const XPColumnLive;
