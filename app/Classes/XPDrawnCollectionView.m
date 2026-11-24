//
//  XPDrawnCollectionView.m
//

#import "XPDrawnCollectionView.h"

static const CGFloat XPDrawnHeaderHeight = 26.0f;

@interface XPDrawnCollectionView ()
@property (nonatomic, strong) NSMutableDictionary *cellClasses;
@property (nonatomic, strong) NSMutableDictionary *reuseQueues;
@property (nonatomic, strong) NSMutableArray *sectionItemFrames;
@property (nonatomic, strong) NSMutableArray *sectionHeaderFrames;
@property (nonatomic, strong) NSMutableArray *visibleCellsBySection;
@property (nonatomic, strong) NSMutableDictionary *visibleHeaders;
@property (nonatomic, strong) Class headerClass;
@property (nonatomic, copy) NSString *headerIdentifier;
@property (nonatomic, assign) CGFloat lastLayoutWidth;
@end

@implementation XPDrawnCollectionView

- (instancetype)initWithFrame:(CGRect)frame
{
  self = [super initWithFrame:frame];
  if (self) {
    self.backgroundColor = [UIColor clearColor];
    self.scrollsHorizontally = NO;
    self.scrollsVertically = YES;
    _cellClasses = [[NSMutableDictionary alloc] init];
    _reuseQueues = [[NSMutableDictionary alloc] init];
    _sectionItemFrames = [[NSMutableArray alloc] init];
    _sectionHeaderFrames = [[NSMutableArray alloc] init];
    _visibleCellsBySection = [[NSMutableArray alloc] init];
    _visibleHeaders = [[NSMutableDictionary alloc] init];
    _itemSize = CGSizeZero;
    _itemAspect = 1.45f;
    _columns = 0;
    _lastLayoutWidth = 0.0f;
    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    [self addGestureRecognizer:tap];
  }
  return self;
}

- (void)setItemSize:(CGSize)itemSize
{
  _itemSize = itemSize;
  [self reloadData];
}

- (void)setColumns:(NSInteger)columns
{
  _columns = columns;
  [self reloadData];
}

- (void)registerCellClass:(Class)cellClass forReuseIdentifier:(NSString *)identifier
{
  if (cellClass == Nil || identifier.length == 0) {
    return;
  }
  self.cellClasses[identifier] = cellClass;
  if (self.reuseQueues[identifier] == nil) {
    self.reuseQueues[identifier] = [[NSMutableArray alloc] init];
  }
}

- (void)registerSupplementaryClass:(Class)viewClass
                    forElementKind:(NSString *)kind
                withReuseIdentifier:(NSString *)identifier
{
  if (viewClass == Nil) {
    return;
  }
  self.headerClass = viewClass;
  self.headerIdentifier = [identifier copy];
}

- (XPDrawnCollectionViewCell *)dequeueReusableCellWithReuseIdentifier:(NSString *)identifier
                                                      forIndexPath:(NSIndexPath *)indexPath
{
  if (identifier.length == 0) {
    return nil;
  }
  NSMutableArray *queue = self.reuseQueues[identifier];
  if (queue == nil) {
    queue = [[NSMutableArray alloc] init];
    self.reuseQueues[identifier] = queue;
  }
  if (queue.count > 0) {
    XPDrawnCollectionViewCell *cell = [queue lastObject];
    [queue removeLastObject];
    [cell prepareForReuse];
    return cell;
  }
  Class cellClass = self.cellClasses[identifier];
  if (cellClass == Nil) {
    return nil;
  }
  XPDrawnCollectionViewCell *cell = [[cellClass alloc] init];
  cell.reuseIdentifier = identifier;
  return cell;
}

- (UIView *)dequeueReusableSupplementaryViewOfKind:(NSString *)kind
                                withReuseIdentifier:(NSString *)identifier
                                       forIndexPath:(NSIndexPath *)indexPath
{
  if (self.headerClass == Nil) {
    return nil;
  }
  UIView *view = [[self.headerClass alloc] initWithFrame:CGRectZero];
  view.backgroundColor = [UIColor clearColor];
  return view;
}

- (NSInteger)numberOfSections
{
  id<XPDrawnCollectionViewDataSource> dataSource = self.dataSource;
  if (dataSource == nil) {
    return 0;
  }
  if ([dataSource respondsToSelector:@selector(numberOfSectionsInCollectionView:)]) {
    return MAX(0, [dataSource numberOfSectionsInCollectionView:self]);
  }
  return 1;
}

- (NSInteger)numberOfItemsInSection:(NSInteger)section
{
  id<XPDrawnCollectionViewDataSource> dataSource = self.dataSource;
  if (dataSource == nil) {
    return 0;
  }
  return MAX(0, [dataSource collectionView:self numberOfItemsInSection:section]);
}

- (UIEdgeInsets)insetForSection:(NSInteger)section
{
  id<XPDrawnCollectionViewDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(collectionView:insetForSectionAtIndex:)]) {
    return [delegate collectionView:self insetForSectionAtIndex:section];
  }
  return UIEdgeInsetsMake(0.0f, 12.0f, 18.0f, 12.0f);
}

- (CGFloat)lineSpacingForSection:(NSInteger)section
{
  id<XPDrawnCollectionViewDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(collectionView:minimumLineSpacingForSectionAtIndex:)]) {
    return [delegate collectionView:self minimumLineSpacingForSectionAtIndex:section];
  }
  return 14.0f;
}

- (CGFloat)interitemSpacingForSection:(NSInteger)section
{
  id<XPDrawnCollectionViewDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(collectionView:minimumInteritemSpacingForSectionAtIndex:)]) {
    return [delegate collectionView:self minimumInteritemSpacingForSectionAtIndex:section];
  }
  return 8.0f;
}

- (BOOL)hasHeaderView
{
  id<XPDrawnCollectionViewDelegate> delegate = self.delegate;
  return [delegate respondsToSelector:
            @selector(collectionView:viewForSupplementaryElementOfKind:atIndexPath:)];
}

- (void)computeLayout
{
  [self.sectionItemFrames removeAllObjects];
  [self.sectionHeaderFrames removeAllObjects];

  CGFloat width = self.bounds.size.width;
  if (width <= 0.0f) {
    width = self.frame.size.width;
  }
  if (width <= 0.0f) {
    self.contentSize = CGSizeZero;
    return;
  }

  NSInteger sections = [self numberOfSections];
  CGFloat y = 0.0f;
  BOOL headerEnabled = [self hasHeaderView];

  for (NSInteger section = 0; section < sections; section++) {
    UIEdgeInsets inset = [self insetForSection:section];
    CGFloat lineSpacing = [self lineSpacingForSection:section];
    CGFloat interitem = [self interitemSpacingForSection:section];
    NSInteger count = [self numberOfItemsInSection:section];
    y += inset.top;

    NSValue *headerFrame = nil;
    if (headerEnabled) {
      headerFrame = [NSValue valueWithCGRect:
          CGRectMake(inset.left, y, MAX(0.0f, width - inset.left - inset.right),
                     XPDrawnHeaderHeight)];
      y += XPDrawnHeaderHeight;
    }
    [self.sectionHeaderFrames addObject:headerFrame ?: (id)[NSNull null]];

    NSMutableArray *frames = [NSMutableArray array];
    if (count > 0) {
      CGFloat available = width - inset.left - inset.right;
      if (available <= 0.0f) {
        available = width;
      }
      NSInteger cols = self.columns;
      if (cols <= 0) {
        CGFloat refWidth = self.itemSize.width > 0.0f ? self.itemSize.width : 150.0f;
        cols = (NSInteger)floor((available + interitem) / (refWidth + interitem));
        cols = MAX(1, cols);
      }
      CGFloat itemWidth = (available - (CGFloat)(cols - 1) * interitem) / (CGFloat)cols;
      if (itemWidth <= 0.0f) {
        itemWidth = available;
        cols = 1;
      }
      CGFloat aspect = self.itemAspect > 0.0f ? self.itemAspect : 1.45f;
      CGFloat itemHeight = self.itemSize.height > 0.0f ? self.itemSize.height : itemWidth * aspect;

      for (NSInteger index = 0; index < count; index++) {
        NSInteger col = index % cols;
        NSInteger row = index / cols;
        CGRect frame = CGRectMake(inset.left + (CGFloat)col * (itemWidth + interitem),
                                  y + (CGFloat)row * (itemHeight + lineSpacing),
                                  itemWidth,
                                  itemHeight);
        [frames addObject:[NSValue valueWithCGRect:frame]];
      }

      NSInteger rows = (count + cols - 1) / cols;
      y += (CGFloat)rows * itemHeight + (CGFloat)MAX(0, rows - 1) * lineSpacing;
    }
    y += inset.bottom;
    [self.sectionItemFrames addObject:frames];
  }

  CGFloat contentHeight = MAX(y, self.bounds.size.height);
  self.contentSize = CGSizeMake(width, contentHeight);
}

- (NSMutableDictionary *)visibleCellsForSection:(NSInteger)section
{
  while ((NSInteger)self.visibleCellsBySection.count <= section) {
    [self.visibleCellsBySection addObject:[[NSMutableDictionary alloc] init]];
  }
  return self.visibleCellsBySection[(NSUInteger)section];
}

- (void)recycleCell:(XPDrawnCollectionViewCell *)cell
{
  [cell removeFromSuperview];
  [cell prepareForReuse];
  NSString *identifier = cell.reuseIdentifier;
  if (identifier.length == 0) {
    return;
  }
  NSMutableArray *queue = self.reuseQueues[identifier];
  if (queue == nil) {
    queue = [[NSMutableArray alloc] init];
    self.reuseQueues[identifier] = queue;
  }
  [queue addObject:cell];
}

- (void)layoutVisibleCells
{
  CGRect visible = CGRectInset(self.bounds, -200.0f, -200.0f);
  NSInteger sections = (NSInteger)self.sectionItemFrames.count;
  NSMutableSet *keepSections = [NSMutableSet set];

  for (NSInteger section = 0; section < sections; section++) {
    id headerValue = self.sectionHeaderFrames[(NSUInteger)section];
    if ([headerValue isKindOfClass:[NSValue class]]) {
      CGRect headerFrame = [(NSValue *)headerValue CGRectValue];
      if (CGRectIntersectsRect(headerFrame, visible)) {
        NSNumber *key = @(section);
        [keepSections addObject:key];
        UIView *header = self.visibleHeaders[key];
        if (header == nil) {
          id<XPDrawnCollectionViewDelegate> delegate = self.delegate;
          if ([delegate respondsToSelector:
                @selector(collectionView:viewForSupplementaryElementOfKind:atIndexPath:)]) {
            header = [delegate collectionView:self
                viewForSupplementaryElementOfKind:UICollectionElementKindSectionHeader
                                      atIndexPath:[NSIndexPath indexPathForItem:0 inSection:section]];
          }
          if (header != nil) {
            self.visibleHeaders[key] = header;
            [self addSubview:header];
          }
        }
        if (header != nil) {
          header.frame = headerFrame;
        }
      }
    }

    NSArray *frames = self.sectionItemFrames[(NSUInteger)section];
    NSMutableDictionary *visibleCells = [self visibleCellsForSection:section];
    NSMutableSet *keep = [NSMutableSet set];

    for (NSInteger index = 0; index < (NSInteger)frames.count; index++) {
      CGRect frame = [frames[(NSUInteger)index] CGRectValue];
      if (!CGRectIntersectsRect(frame, visible)) {
        continue;
      }
      NSNumber *key = @(index);
      [keep addObject:key];
      XPDrawnCollectionViewCell *cell = visibleCells[key];
      if (cell == nil) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForItem:index inSection:section];
        cell = [self.dataSource collectionView:self cellForItemAtIndexPath:indexPath];
        if (cell == nil) {
          continue;
        }
        visibleCells[key] = cell;
        [self addSubview:cell];
      }
      cell.frame = frame;
    }

    for (NSNumber *key in [visibleCells.allKeys copy]) {
      if ([keep containsObject:key]) {
        continue;
      }
      XPDrawnCollectionViewCell *cell = visibleCells[key];
      [visibleCells removeObjectForKey:key];
      if (cell != nil) {
        [self recycleCell:cell];
      }
    }
  }

  for (NSNumber *key in [self.visibleHeaders.allKeys copy]) {
    if ([keepSections containsObject:key]) {
      continue;
    }
    UIView *header = self.visibleHeaders[key];
    [self.visibleHeaders removeObjectForKey:key];
    [header removeFromSuperview];
  }
}

- (void)reloadData
{
  for (NSMutableDictionary *visibleCells in self.visibleCellsBySection) {
    for (NSNumber *key in [visibleCells.allKeys copy]) {
      XPDrawnCollectionViewCell *cell = visibleCells[key];
      [visibleCells removeObjectForKey:key];
      if (cell != nil) {
        [self recycleCell:cell];
      }
    }
  }
  for (NSNumber *key in [self.visibleHeaders.allKeys copy]) {
    UIView *header = self.visibleHeaders[key];
    [self.visibleHeaders removeObjectForKey:key];
    [header removeFromSuperview];
  }
  [self computeLayout];
  [self layoutVisibleCells];
}

- (void)setContentOffset:(CGPoint)contentOffset
{
  [super setContentOffset:contentOffset];
  [self layoutVisibleCells];
}

- (void)setContentOffset:(CGPoint)contentOffset animated:(BOOL)animated
{
  [super setContentOffset:contentOffset animated:animated];
  [self layoutVisibleCells];
  if (animated) {
    __weak XPDrawnCollectionView *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.28 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
      [weakSelf layoutVisibleCells];
    });
  }
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  CGFloat width = self.bounds.size.width;
  if (width <= 0.0f) {
    return;
  }
  if (fabs(width - self.lastLayoutWidth) > 0.5f) {
    self.lastLayoutWidth = width;
    [self reloadData];
    return;
  }
  [self layoutVisibleCells];
}

- (void)handleTap:(UITapGestureRecognizer *)tap
{
  if (tap.state != UIGestureRecognizerStateEnded) {
    return;
  }
  CGPoint content = [tap locationInView:self];
  NSInteger sections = (NSInteger)self.sectionItemFrames.count;
  for (NSInteger section = 0; section < sections; section++) {
    NSArray *frames = self.sectionItemFrames[(NSUInteger)section];
    for (NSInteger index = (NSInteger)frames.count - 1; index >= 0; index--) {
      CGRect frame = [frames[(NSUInteger)index] CGRectValue];
      if (!CGRectContainsPoint(frame, content)) {
        continue;
      }
      id<XPDrawnCollectionViewDelegate> delegate = self.delegate;
      if ([delegate respondsToSelector:@selector(collectionView:didSelectItemAtIndexPath:)]) {
        [delegate collectionView:self
            didSelectItemAtIndexPath:[NSIndexPath indexPathForItem:index inSection:section]];
      }
      return;
    }
  }
}

@end
