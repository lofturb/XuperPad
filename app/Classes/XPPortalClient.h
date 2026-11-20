//
//  XPPortalClient.h
//  Cliente del catalogo, busqueda, detalle y reproduccion del portal.
//

#import <Foundation/Foundation.h>

/// Se invoca al obtener una lista de titulos del catalogo.
typedef void (^XPTitleListCompletion)(NSArray *titles, NSError *error);

/// Se invoca al obtener el detalle de un titulo.
typedef void (^XPTitleDetailCompletion)(NSDictionary *detail, NSError *error);

/// Cliente del portal XuperTV.
@interface XPPortalClient : NSObject

/// Cliente compartido por toda la aplicacion.
+ (instancetype)sharedClient;

/// Titulos de una columna del catalogo.
- (void)fetchTitlesForColumn:(NSString *)columnCode
                        page:(NSUInteger)page
                  completion:(XPTitleListCompletion)completion;

/// Filas de una columna con el nombre de cada seccion.
- (void)fetchSectionsForColumn:(NSString *)columnCode
                           page:(NSUInteger)page
                     completion:(void (^)(NSArray *sections, NSError *error))completion;

/// Resultados de una busqueda por nombre.
- (void)searchTitles:(NSString *)text
                 page:(NSUInteger)page
           completion:(XPTitleListCompletion)completion;

/// Detalle de un titulo, con su lista de capitulos.
- (void)fetchDetailForTitle:(NSString *)contentId
                     isSeries:(BOOL)isSeries
                   completion:(XPTitleDetailCompletion)completion;

/// Canales de television en vivo.
- (void)fetchLiveChannelsForColumn:(NSString *)columnIdentifier
                               page:(NSUInteger)page
                         completion:(XPTitleListCompletion)completion;

/// Categorias de television en vivo.
- (void)fetchLiveCategoriesWithCompletion:(XPTitleListCompletion)completion;

/// Llamada generica al portal, para las rutas de reproduccion y balanceo.
- (void)fetchStreamInformationForPath:(NSString *)path
                            parameters:(NSDictionary *)parameters
                             completion:(void (^)(NSDictionary *response, NSError *error))completion;

@end
