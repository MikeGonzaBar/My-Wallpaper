#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const MWScreenSaverDisplayClaimsDidResetNotification;
FOUNDATION_EXPORT NSNotificationName const MWScreenSaverDisplayClaimWasDisplacedNotification;

@interface MWScreenSaverDisplay : NSObject

@property(nonatomic, copy, readonly) NSString *displayID;
@property(nonatomic, readonly) NSSize size;

- (instancetype)initWithDisplayID:(NSString *)displayID size:(NSSize)size;

@end

typedef NSArray<MWScreenSaverDisplay *> * _Nonnull (^MWScreenSaverDisplayProvider)(void);

@interface MWScreenSaverDisplayResolver : NSObject

+ (instancetype)sharedResolver;
- (instancetype)initWithDisplayProvider:(MWScreenSaverDisplayProvider)displayProvider;
- (void)beginAnimationForOwner:(id)owner;
- (nullable NSString *)displayIDForOwner:(id)owner
                                  screen:(nullable NSScreen *)screen
                                viewSize:(NSSize)viewSize;
- (void)releaseDisplayForOwner:(id)owner;

@end

NS_ASSUME_NONNULL_END
