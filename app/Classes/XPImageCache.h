//
//  XPImageCache.h
//

#import <UIKit/UIKit.h>

@interface XPImageCache : NSObject

+ (instancetype)sharedCache;

- (UIImage *)imageForAddress:(NSString *)address;

- (void)loadImageForAddress:(NSString *)address
                  completion:(void (^)(UIImage *image))completion;

@end
