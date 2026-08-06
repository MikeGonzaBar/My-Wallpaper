#import <AppKit/AppKit.h>

#import "ScreenSaverDisplayResolver.h"

@interface MWScreenSaverDisplayResolver (Testing)
- (nullable NSString *)displayIDForOwner:(id)owner
                       preferredDisplayID:(nullable NSString *)preferredDisplayID
                                 viewSize:(NSSize)viewSize;
- (void)beginAnimationForOwner:(id)owner atTime:(NSTimeInterval)startTime;
@end

static void Require(BOOL condition, NSString *message) {
    if (!condition) {
        NSLog(@"FAILED: %@", message);
        exit(1);
    }
}

static MWScreenSaverDisplay *Display(NSString *displayID, CGFloat width, CGFloat height) {
    return [[MWScreenSaverDisplay alloc]
        initWithDisplayID:displayID
                     size:NSMakeSize(width, height)];
}

int main(void) {
    @autoreleasepool {
        NSArray<MWScreenSaverDisplay *> *displays = @[
            Display(@"built-in", 1512, 982),
            Display(@"external-a", 3440, 1440),
            Display(@"external-b", 3440, 1440),
        ];
        MWScreenSaverDisplayResolver *resolver = [[MWScreenSaverDisplayResolver alloc]
            initWithDisplayProvider:^NSArray<MWScreenSaverDisplay *> *{
                return displays;
            }];

        NSObject *firstExternal = [[NSObject alloc] init];
        NSObject *secondExternal = [[NSObject alloc] init];
        NSObject *builtIn = [[NSObject alloc] init];

        NSString *firstID = [resolver displayIDForOwner:firstExternal
                                                 screen:nil
                                               viewSize:NSMakeSize(3440, 1440)];
        NSString *secondID = [resolver displayIDForOwner:secondExternal
                                                  screen:nil
                                                viewSize:NSMakeSize(3440, 1440)];
        NSString *builtInID = [resolver displayIDForOwner:builtIn
                                                   screen:nil
                                                 viewSize:NSMakeSize(1512, 982)];

        Require([firstID isEqualToString:@"external-a"],
                @"The first detached external view should claim the first matching display");
        Require([secondID isEqualToString:@"external-b"],
                @"Identical detached external views must claim different displays");
        Require([builtInID isEqualToString:@"built-in"],
                @"A detached built-in view should resolve by its pixel dimensions");
        Require([[resolver displayIDForOwner:firstExternal
                                       screen:nil
                                     viewSize:NSMakeSize(3440, 1440)] isEqualToString:firstID],
                @"A view should retain its display assignment across layout passes");

        [resolver releaseDisplayForOwner:firstExternal];
        NSObject *replacementExternal = [[NSObject alloc] init];
        Require([[resolver displayIDForOwner:replacementExternal
                                       screen:nil
                                     viewSize:NSMakeSize(3440, 1440)] isEqualToString:@"external-a"],
                @"Stopping a view should release its display for a replacement view");

        MWScreenSaverDisplayResolver *takeoverResolver = [[MWScreenSaverDisplayResolver alloc]
            initWithDisplayProvider:^NSArray<MWScreenSaverDisplay *> *{
                return displays;
            }];
        NSObject *staleBuiltInView = [[NSObject alloc] init];
        NSObject *visibleBuiltInView = [[NSObject alloc] init];
        Require([[takeoverResolver displayIDForOwner:staleBuiltInView
                                  preferredDisplayID:@"built-in"
                                            viewSize:NSMakeSize(1512, 982)] isEqualToString:@"built-in"],
                @"The first attached view should claim its exact screen");
        Require([[takeoverResolver displayIDForOwner:visibleBuiltInView
                                  preferredDisplayID:@"built-in"
                                            viewSize:NSMakeSize(1512, 982)] isEqualToString:@"built-in"],
                @"A newer attached view should take over its exact screen from a stale view");
        Require([takeoverResolver displayIDForOwner:staleBuiltInView
                                 preferredDisplayID:nil
                                           viewSize:NSMakeSize(1512, 982)] == nil,
                @"The displaced stale view should no longer own the attached display");

        MWScreenSaverDisplayResolver *sessionResolver = [[MWScreenSaverDisplayResolver alloc]
            initWithDisplayProvider:^NSArray<MWScreenSaverDisplay *> *{
                return displays;
            }];
        NSObject *firstSessionView = [[NSObject alloc] init];
        NSObject *firstSessionExternal = [[NSObject alloc] init];
        [sessionResolver beginAnimationForOwner:firstSessionView atTime:10.0];
        Require([[sessionResolver displayIDForOwner:firstSessionExternal
                                              screen:nil
                                            viewSize:NSMakeSize(3440, 1440)]
                    isEqualToString:@"external-a"],
                @"The first activation should claim an external display");

        NSObject *sameSessionView = [[NSObject alloc] init];
        [sessionResolver beginAnimationForOwner:sameSessionView atTime:11.0];
        Require([[sessionResolver displayIDForOwner:[[NSObject alloc] init]
                                              screen:nil
                                            viewSize:NSMakeSize(3440, 1440)]
                    isEqualToString:@"external-b"],
                @"Views joining the same activation must preserve existing claims");

        NSObject *nextSessionView = [[NSObject alloc] init];
        [sessionResolver beginAnimationForOwner:nextSessionView atTime:14.0];
        Require([[sessionResolver displayIDForOwner:nextSessionView
                                              screen:nil
                                            viewSize:NSMakeSize(3440, 1440)]
                    isEqualToString:@"external-a"],
                @"A later activation should release stale external display claims");

        MWScreenSaverDisplayResolver *ambiguousResolver = [[MWScreenSaverDisplayResolver alloc]
            initWithDisplayProvider:^NSArray<MWScreenSaverDisplay *> *{
                return displays;
            }];
        Require([ambiguousResolver displayIDForOwner:[[NSObject alloc] init]
                                               screen:nil
                                             viewSize:NSMakeSize(100, 100)] == nil,
                @"An unknown view must not be assigned while multiple displays are available");

        printf("Screen saver display resolver tests passed.\n");
    }
    return 0;
}
