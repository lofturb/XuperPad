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

/// Codificacion de video declarada por el portal.
@property (nonatomic, copy) NSString *streamCodec;

/// Formato del archivo de video declarado por el portal.
@property (nonatomic, copy) NSString *streamFormat;

/// Identificador de la serie a la que pertenece el capitulo.
@property (nonatomic, copy) NSString *seriesId;

/// Identificador del capitulo o titulo en reproduccion.
@property (nonatomic, copy) NSString *contentId;

/// Nombre de la serie a la que pertenece el capitulo.
@property (nonatomic, copy) NSString *seriesName;

/// Lista de capitulos disponibles para navegar.
@property (nonatomic, copy) NSArray *chapters;

/// Indice del capitulo que se esta reproduciendo.
@property (nonatomic, assign) NSInteger currentChapterIndex;

/// Caratula del titulo para el historial.
@property (nonatomic, copy) NSString *posterAddress;

/// Imagen de fondo del titulo para el historial.
@property (nonatomic, copy) NSString *backdropAddress;

/// Segundo desde el que debe empezar la reproduccion.
@property (nonatomic, assign) double startPosition;

/// Crea el reproductor con los datos de una direccion resuelta.
+ (instancetype)playerWithStream:(NSDictionary *)stream;

@end
