//
//  XPCatalogViewController.h
//  Lista del catalogo con navegacion por columnas y busqueda.
//

#import <UIKit/UIKit.h>

/// Pantalla principal con el catalogo completo del portal.
@interface XPCatalogViewController : UIViewController

/// Titulo inicial de la pantalla.
@property (nonatomic, copy) NSString *screenTitle;

/// Indica si la pantalla muestra television en vivo en lugar de catalogo.
@property (nonatomic, assign) BOOL showsLiveChannels;

@end
