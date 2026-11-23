//
//  XPDrawnCollectionViewCell.h
//

#import <UIKit/UIKit.h>

@interface XPDrawnCollectionViewCell : UIView

@property (nonatomic, copy) NSString *reuseIdentifier;
@property (nonatomic, assign, getter=isSelected) BOOL selected;
@property (nonatomic, readonly) UIView *contentView;

- (instancetype)initWithReuseIdentifier:(NSString *)reuseIdentifier;
- (void)prepareForReuse;
- (void)setSelected:(BOOL)selected;

@end
