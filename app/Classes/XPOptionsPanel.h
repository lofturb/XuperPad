#import <UIKit/UIKit.h>

@interface XPOptionsPanel : UIView

@property (nonatomic, copy) NSArray *audioTracks;
@property (nonatomic, copy) NSArray *subtitleTracks;
@property (nonatomic, assign) NSInteger selectedAudioIndex;
@property (nonatomic, assign) NSInteger selectedSubtitleIndex;
@property (nonatomic, assign) float playbackRate;
@property (nonatomic, copy) NSString *informationText;

@property (nonatomic, copy) void (^audioSelectionHandler)(NSInteger index);
@property (nonatomic, copy) void (^subtitleSelectionHandler)(NSInteger index);
@property (nonatomic, copy) void (^rateSelectionHandler)(float rate);
@property (nonatomic, copy) void (^closeHandler)(void);

@end
