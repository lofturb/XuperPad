//
//  XPTabBar.h
//

#import <UIKit/UIKit.h>

typedef void (^XPTabSelectionHandler)(NSUInteger index);

@interface XPTabBar : UIView

- (instancetype)initWithTitles:(NSArray *)titles icons:(NSArray *)icons;

@property (nonatomic, copy) XPTabSelectionHandler selectionHandler;
@property (nonatomic, assign) NSUInteger selectedIndex;

@end
