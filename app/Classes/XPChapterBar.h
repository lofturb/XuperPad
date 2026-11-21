#import <UIKit/UIKit.h>

@interface XPChapterBar : UIView

@property (nonatomic, copy) NSArray *chapters;
@property (nonatomic, assign) NSInteger currentIndex;
@property (nonatomic, copy) void (^previousHandler)(void);
@property (nonatomic, copy) void (^nextHandler)(void);
@property (nonatomic, copy) void (^selectionHandler)(NSInteger index);

@end
