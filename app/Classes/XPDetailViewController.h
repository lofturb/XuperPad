//
//  XPDetailViewController.h
//  Detalle de un titulo con su lista de capitulos.
//

#import <UIKit/UIKit.h>

/// Pantalla de detalle de una pelicula o serie.
@interface XPDetailViewController : UIViewController

/// Crea el detalle a partir de los datos del catalogo.
- (instancetype)initWithTitle:(NSDictionary *)title;

@end
