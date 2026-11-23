//
//  XPCardCell.m
//

#import "XPCardCell.h"
#import "XPTheme.h"
#import "XPImageCache.h"
#import "XPDrawnImageView.h"
#import "XPDrawnLabel.h"

@interface XPCardShadeView : UIView
@end

@implementation XPCardShadeView

- (void)drawRect:(CGRect)rect
{
  CGContextRef context = UIGraphicsGetCurrentContext();
  if (context == NULL) {
    return;
  }
  [[UIColor clearColor] setFill];
  CGContextFillRect(context, rect);
  XPDrawVerticalGradient(context,
                         rect,
                         [UIColor colorWithWhite:0.0f alpha:0.0f],
                         [UIColor colorWithWhite:0.0f alpha:0.75f]);
}

@end

@interface XPCardCell ()
@property (nonatomic, strong) XPDrawnImageView *posterView;
@property (nonatomic, strong) XPCardShadeView *shadeView;
@property (nonatomic, strong) XPDrawnLabel *titleLabel;
@property (nonatomic, strong) XPDrawnLabel *badgeLabel;
@property (nonatomic, copy) NSString *posterAddress;
@end

@implementation XPCardCell

- (instancetype)initWithFrame:(CGRect)frame
{
  self = [super initWithFrame:frame];
  if (self) {
    self.backgroundColor = [UIColor clearColor];
    self.contentView.backgroundColor = [UIColor clearColor];

    self.posterView = [[XPDrawnImageView alloc] initWithFrame:CGRectZero];
    self.posterView.imageMode = XPDrawnImageModeFill;
    self.posterView.cornerRadius = 8.0f;
    self.posterView.fillColor = XPColorSurface();
    [self.contentView addSubview:self.posterView];

    self.shadeView = [[XPCardShadeView alloc] initWithFrame:CGRectZero];
    self.shadeView.backgroundColor = [UIColor clearColor];
    self.shadeView.userInteractionEnabled = NO;
    [self.contentView addSubview:self.shadeView];

    self.badgeLabel = [[XPDrawnLabel alloc] initWithFrame:CGRectZero];
    self.badgeLabel.font = [UIFont systemFontOfSize:7.5f weight:UIFontWeightBold];
    self.badgeLabel.textColor = [UIColor whiteColor];
    self.badgeLabel.textAlignment = NSTextAlignmentCenter;
    self.badgeLabel.layer.backgroundColor = XPColorAccent().CGColor;
    self.badgeLabel.layer.cornerRadius = 3.0f;
    self.badgeLabel.layer.masksToBounds = YES;
    self.badgeLabel.hidden = YES;
    [self.contentView addSubview:self.badgeLabel];

    self.titleLabel = [[XPDrawnLabel alloc] initWithFrame:CGRectZero];
    self.titleLabel.font = XPFontCaption(10.5f);
    self.titleLabel.textColor = XPColorTextPrimary();
    self.titleLabel.numberOfLines = 2;
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.contentView addSubview:self.titleLabel];
  }
  return self;
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  CGFloat width = CGRectGetWidth(self.bounds);
  CGFloat height = CGRectGetHeight(self.bounds);
  CGFloat textHeight = 32.0f;
  CGFloat posterHeight = MAX(40.0f, height - textHeight);

  self.posterView.frame = CGRectMake(0, 0, width, posterHeight);
  self.shadeView.frame = CGRectMake(0, posterHeight - 44.0f, width, 44.0f);
  self.titleLabel.frame = CGRectMake(0, posterHeight + 4.0f, width, textHeight - 6.0f);

  if (!self.badgeLabel.hidden) {
    self.badgeLabel.frame = CGRectMake(5.0f, 5.0f, 34.0f, 13.0f);
  }
}

- (void)applyTitle:(NSDictionary *)title
{
  NSString *name = title[@"name"];
  self.titleLabel.text = name ?: @"";

  BOOL series = [title[@"series"] boolValue];
  self.badgeLabel.hidden = !series;
  self.badgeLabel.text = @"SERIE";

  NSString *address = title[@"poster"];
  self.posterAddress = address;
  self.posterView.image = [[XPImageCache sharedCache] imageForAddress:address];
  if (self.posterView.image != nil || address.length == 0) {
    return;
  }

  __weak XPCardCell *weakSelf = self;
  [[XPImageCache sharedCache] loadImageForAddress:address
                                       completion:^(UIImage *image) {
    if (image == nil) {
      return;
    }
    if ([weakSelf.posterAddress isEqualToString:address]) {
      weakSelf.posterView.image = image;
    }
  }];
}

- (void)prepareForReuse
{
  [super prepareForReuse];
  self.posterView.image = nil;
  self.posterAddress = nil;
  self.titleLabel.text = @"";
  self.badgeLabel.hidden = YES;
}

@end
