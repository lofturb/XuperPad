//
//  XPPortalParser.h
//  Convierte las respuestas del portal en estructuras simples.
//

#import <Foundation/Foundation.h>

/// Extrae la lista de titulos de una columna del catalogo.
@interface XPPortalParser : NSObject

/// Titulos de una columna: devuelve objetos con id, nombre, caratula y resumen.
+ (NSArray *)titlesFromColumnResponse:(NSDictionary *)response;

/// Filas de una columna con su nombre de seccion.
+ (NSArray *)sectionsFromColumnResponse:(NSDictionary *)response;

/// Titulos de una busqueda por nombre.
+ (NSArray *)titlesFromSearchResponse:(NSDictionary *)response;

/// Canales de television en vivo.
+ (NSArray *)channelsFromLiveResponse:(NSDictionary *)response;

/// Categorias de television en vivo.
+ (NSArray *)categoriesFromColumnResponse:(NSDictionary *)response;

/// Detalle de un titulo, con su lista de capitulos.
+ (NSDictionary *)detailFromResponse:(NSDictionary *)response;

/// Pistas de video de una respuesta de reproduccion.
+ (NSArray *)tracksFromPlayResponse:(NSDictionary *)response;

/// Direcciones de CDN de video de contenido libre.
+ (NSArray *)videoOriginsFromSlbResponse:(NSDictionary *)response;

/// Direcciones de CDN de television en vivo con su cabecera de autenticacion.
+ (NSArray *)liveOriginsFromSlbResponse:(NSDictionary *)response;

/// Licencias de reproduccion de una respuesta de inicio de video.
+ (NSArray *)licensesFromPlayResponse:(NSDictionary *)response;

@end
