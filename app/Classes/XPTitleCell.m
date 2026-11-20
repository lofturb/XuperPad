//
//  XPTitleCell.m
//

#import "XPTitleCell.h"

@interface XPTitleCell ()
@property (nonatomic, strong) UIImageView *posterView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@end

@implementation XPTitleCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier
{
  self = [super initWithStyle:style reuseIdentifier:identifier];
  if (self) {
    [self buildInterface];
  }
  return self;
}

- (void)buildInterface
{
  self.posterView = [[UIImageView alloc] initWithFrame:CGRectZero];
  self.posterView.contentMode = UIViewContentModeScaleAspectFill;
  self.posterView.clipsToBounds = YES;
  self.posterView.backgroundColor = [UIColor colorWithWhite:0.16 alpha:1.0];
  [self.contentView addSubview:self.posterView];

  self.nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
  self.nameLabel.font = [UIFont systemFontOfSize:16];
  self.nameLabel.numberOfLines = 2;
  [self.contentView addSubview:self.nameLabel];

  self.subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
  self.subtitleLabel.font = [UIFont systemFontOfSize:13];
  self.subtitleLabel.textColor = [UIColor grayColor];
  [self.contentView addSubview:self.subtitleLabel];
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  CGFloat margin = 10;
  CGFloat posterWidth = 60;
  CGFloat posterHeight = 84;
  CGFloat originX = margin;
  CGFloat originY = (self.contentView.bounds.size.height - posterHeight) / 2;

  self.posterView.frame = CGRectMake(originX, originY, posterWidth, posterHeight);
  self.nameLabel.frame = CGRectMake(originX + posterWidth + margin,
                                    originY + 8,
                                    self.contentView.bounds.size.width - originX - posterWidth - margin * 2,
                                    40);
  self.subtitleLabel.frame = CGRectMake(originX + posterWidth + margin,
                                        originY + 52,
                                        self.contentView.bounds.size.width - originX - posterWidth - margin * 2,
                                        20);
}

- (void)applyTitle:(NSDictionary *)title
{
  self.titleIdentifier = title[@"id"];
  self.titleName = title[@"name"];
  self.posterAddress = title[@"poster"];
  self.nameLabel.text = self.titleName;

  NSMutableArray *parts = [NSMutableArray array];
  NSString *year = title[@"year"];
  if (year.length > 0) {
    [parts addObject:year];
  }
  NSString *score = title[@"score"];
  if (score.length > 0) {
    [parts addObject:score];
  }
  self.titleSubtitle = [parts componentsJoinedByString:@"  "];
  self.subtitleLabel.text = self.titleSubtitle;

  self.posterView.image = nil;
  NSString *address = self.posterAddress;
  if (address.length == 0) {
    return;
  }
  NSURL *url = [NSURL URLWithString:address];
  if (url == nil) {
    return;
  }

  NSURLSessionDataTask *task =
      [[NSURLSession sharedSession] dataTaskWithURL:url
                                   completionHandler:^(NSData *data,
                                                       NSURLResponse *response,
                                                       NSError *error) {
    if (data == nil || error != nil) {
      return;
    }
    UIImage *image = [UIImage imageWithData:data];
    if (image == nil) {
      return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      if ([self.posterAddress isEqualToString:address]) {
        self.posterView.image = image;
      }
    });
  }];
  [task resume];
}

- (void)prepareForReuse
{
  [super prepareForReuse];
  self.posterView.image = nil;
  self.titleIdentifier = nil;
  self.titleName = nil;
  self.posterAddress = nil;
}

@end
