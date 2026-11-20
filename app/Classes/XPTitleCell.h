//
//  XPTitleCell.h
//  Celda de la lista de titulos.
//

#import <UIKit/UIKit.h>

/// Celda que muestra caratula, titulo y metadatos.
@interface XPTitleCell : UITableViewCell

/// Identificador del titulo.
@property (nonatomic, copy) NSString *titleIdentifier;

/// Nombre del titulo.
@property (nonatomic, copy) NSString *titleName;

/// Texto secundario con ano y puntaje.
@property (nonatomic, copy) NSString *titleSubtitle;

/// Direccion de la caratula.
@property (nonatomic, copy) NSString *posterAddress;

/// Prepara la celda con los datos de un titulo.
- (void)applyTitle:(NSDictionary *)title;

@end
