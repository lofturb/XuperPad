//
//  XPDrawnCollectionView.h
//

#import <UIKit/UIKit.h>
#import "XPDrawnScrollView.h"
#import "XPDrawnCollectionViewCell.h"

@class XPDrawnCollectionView;

@protocol XPDrawnCollectionViewDataSource <NSObject>
- (NSInteger)collectionView:(XPDrawnCollectionView *)collectionView
    numberOfItemsInSection:(NSInteger)section;
- (XPDrawnCollectionViewCell *)collectionView:(XPDrawnCollectionView *)collectionView
                        cellForItemAtIndexPath:(NSIndexPath *)indexPath;
@optional
- (NSInteger)numberOfSectionsInCollectionView:(XPDrawnCollectionView *)collectionView;
@end

@protocol XPDrawnCollectionViewDelegate <NSObject>
@optional
- (void)collectionView:(XPDrawnCollectionView *)collectionView
    didSelectItemAtIndexPath:(NSIndexPath *)indexPath;
- (UIEdgeInsets)collectionView:(XPDrawnCollectionView *)collectionView
        insetForSectionAtIndex:(NSInteger)section;
- (CGFloat)collectionView:(XPDrawnCollectionView *)collectionView
    minimumLineSpacingForSectionAtIndex:(NSInteger)section;
- (CGFloat)collectionView:(XPDrawnCollectionView *)collectionView
    minimumInteritemSpacingForSectionAtIndex:(NSInteger)section;
- (UIView *)collectionView:(XPDrawnCollectionView *)collectionView
    viewForSupplementaryElementOfKind:(NSString *)kind
                          atIndexPath:(NSIndexPath *)indexPath;
@end

@interface XPDrawnCollectionView : XPDrawnScrollView

@property (nonatomic, weak) id<XPDrawnCollectionViewDataSource> dataSource;
@property (nonatomic, weak) id<XPDrawnCollectionViewDelegate> delegate;
@property (nonatomic, assign) CGSize itemSize;
@property (nonatomic, assign) CGFloat itemAspect;
@property (nonatomic, assign) NSInteger columns;

- (void)registerCellClass:(Class)cellClass forReuseIdentifier:(NSString *)identifier;
- (void)registerSupplementaryClass:(Class)viewClass
                    forElementKind:(NSString *)kind
                withReuseIdentifier:(NSString *)identifier;
- (XPDrawnCollectionViewCell *)dequeueReusableCellWithReuseIdentifier:(NSString *)identifier
                                                      forIndexPath:(NSIndexPath *)indexPath;
- (UIView *)dequeueReusableSupplementaryViewOfKind:(NSString *)kind
                                withReuseIdentifier:(NSString *)identifier
                                       forIndexPath:(NSIndexPath *)indexPath;
- (void)reloadData;

@end
