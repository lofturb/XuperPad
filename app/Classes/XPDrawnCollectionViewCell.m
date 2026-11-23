//
//  XPDrawnCollectionViewCell.m
//

#import "XPDrawnCollectionViewCell.h"

@implementation XPDrawnCollectionViewCell

- (instancetype)initWithReuseIdentifier:(NSString *)reuseIdentifier
{
  self = [super initWithFrame:CGRectZero];
  if (self) {
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    _reuseIdentifier = [reuseIdentifier copy];
  }
  return self;
}

- (void)prepareForReuse
{
  _selected = NO;
}

- (UIView *)contentView
{
  return self;
}

@end
