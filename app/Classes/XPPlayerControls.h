#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, XPPlayerControlIcon) {
  XPPlayerControlIconPreviousChapter,
  XPPlayerControlIconPlay,
  XPPlayerControlIconPause,
  XPPlayerControlIconNextChapter,
  XPPlayerControlIconMore
};

@interface XPPlayerControls : UIView

@property (nonatomic, copy) NSString *titleText;
@property (nonatomic, copy) NSString *subtitleText;
@property (nonatomic, assign) double elapsedTime;
@property (nonatomic, assign) double duration;
@property (nonatomic, assign) float progress;
@property (nonatomic, assign, getter=isPlaying) BOOL playing;
@property (nonatomic, assign) BOOL liveStream;

@property (nonatomic, copy) void (^closeHandler)(void);
@property (nonatomic, copy) void (^playPauseHandler)(void);
@property (nonatomic, copy) void (^previousChapterHandler)(void);
@property (nonatomic, copy) void (^nextChapterHandler)(void);
@property (nonatomic, copy) void (^moreHandler)(void);
@property (nonatomic, copy) void (^seekHandler)(float fraction);

@end
