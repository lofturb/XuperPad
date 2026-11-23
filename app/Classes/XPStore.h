//
//  XPStore.h
//  Persistencia local: progreso, historial, favoritos y ajustes.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, XPAspectMode) {
  XPAspectModeFit = 0,
  XPAspectModeFill = 1,
  XPAspectModeStretch = 2
};

@interface XPStore : NSObject

+ (instancetype)sharedStore;

@property (nonatomic, copy) NSString *preferredAudioLanguage;
@property (nonatomic, copy) NSString *preferredSubtitleLanguage;
@property (nonatomic, assign) XPAspectMode aspectMode;

- (void)recordPlaybackWithId:(NSString *)contentId
                        name:(NSString *)name
                    isSeries:(BOOL)isSeries
                      poster:(NSString *)poster
                    backdrop:(NSString *)backdrop
                    chapters:(NSArray *)chapters
            currentChapter:(NSInteger)currentChapter
                  position:(double)position
                  duration:(double)duration;

- (NSArray *)historyEntries;
- (NSDictionary *)historyEntryForId:(NSString *)contentId;
- (void)removeHistoryForId:(NSString *)contentId;
- (void)clearHistory;

- (BOOL)isFavoriteWithId:(NSString *)contentId;
- (void)toggleFavoriteWithTitle:(NSDictionary *)title;
- (NSArray *)favoriteTitles;
- (void)removeFavoriteWithId:(NSString *)contentId;

@end
