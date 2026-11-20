//
//  XPPlayerViewController.h
//  Reproductor de video con AVPlayer.
//

#import <UIKit/UIKit.h>

/// Controlador que reproduce una direccion de video con cabeceras propias.
@interface XPPlayerViewController : UIViewController

/// Titulo mostrado en pantalla.
@property (nonatomic, copy) NSString *titleText;

/// Direccion del video.
@property (nonatomic, copy) NSString *streamAddress;

/// Cabeceras HTTP necesarias para la reproduccion.
@property (nonatomic, copy) NSDictionary *streamHeaders;

/// Direcciones de respaldo cuando la principal falla.
@property (nonatomic, copy) NSArray *backupAddresses;

/// Tipo de contenido declarado por el portal.
@property (nonatomic, copy) NSString *streamType;

/// Crea el reproductor con los datos de una direccion resuelta.
+ (instancetype)playerWithStream:(NSDictionary *)stream;

@end
