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

static void TestReclaimedDisplaysAfterSessionReset(NSArray<MWScreenSaverDisplay *> *displays) {
    MWScreenSaverDisplayResolver *resolver = [[MWScreenSaverDisplayResolver alloc]
        initWithDisplayProvider:^NSArray<MWScreenSaverDisplay *> *{ return displays; }];
    NSObject *builtIn = [[NSObject alloc] init];
    NSArray<NSObject *> *staleViews = @[[NSObject new], [NSObject new]];
    NSArray<NSObject *> *visibleViews = @[[NSObject new], [NSObject new]];
    NSSize externalSize = NSMakeSize(3440, 1440);
    [resolver beginAnimationForOwner:builtIn atTime:10.0];
    for (NSObject *view in staleViews) {
        [resolver beginAnimationForOwner:view atTime:10.1];
        Require([resolver displayIDForOwner:view screen:nil viewSize:externalSize] != nil,
                @"The previous session should claim both external displays");
    }

    [resolver beginAnimationForOwner:builtIn atTime:20.0];
    Require([[resolver displayIDForOwner:builtIn preferredDisplayID:@"built-in"
                               viewSize:NSMakeSize(1512, 982)] isEqualToString:@"built-in"],
            @"The new session should preserve the attached built-in display");
    // Retained views receive layout callbacks without starting in the new session.
    for (NSObject *view in staleViews) {
        Require([resolver displayIDForOwner:view screen:nil viewSize:externalSize] != nil,
                @"Retained views can provisionally reclaim displays after a reset");
    }
    __block NSUInteger displacementCount = 0;
    id observer = [NSNotificationCenter.defaultCenter
        addObserverForName:MWScreenSaverDisplayClaimWasDisplacedNotification object:nil queue:nil
        usingBlock:^(NSNotification *notification) {
            Require([staleViews containsObject:notification.object],
                    @"Only stale external owners should be displaced");
            displacementCount += 1;
        }];
    NSMutableSet<NSString *> *assignedIDs = [NSMutableSet set];
    for (NSObject *view in visibleViews) {
        [resolver beginAnimationForOwner:view atTime:20.5];
        NSString *displayID = [resolver displayIDForOwner:view screen:nil viewSize:externalSize];
        Require(displayID != nil, @"New external views must replace claims without a session start order");
        [assignedIDs addObject:displayID];
    }
    Require([assignedIDs isEqualToSet:[NSSet setWithArray:@[@"external-a", @"external-b"]]],
            @"Both visible external views must receive distinct external displays");
    Require(displacementCount == 2, @"Both stale players must receive a displacement notification");
    for (NSObject *view in staleViews) {
        Require([resolver displayIDForOwner:view screen:nil viewSize:externalSize] == nil,
                @"A stale layout callback must not steal back a visible display");
        Require([resolver displayIDForOwner:view screen:nil viewSize:NSMakeSize(1512, 982)] == nil,
                @"A stale view must not displace the attached built-in view");
        [resolver releaseDisplayForOwner:view];
    }
    for (NSObject *view in visibleViews) {
        Require([assignedIDs containsObject:[resolver displayIDForOwner:view screen:nil viewSize:externalSize]],
                @"Stopping stale views must preserve the replacement claims");
    }
    [NSNotificationCenter.defaultCenter removeObserver:observer];
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

        MWScreenSaverDisplayResolver *delayedViewResolver = [[MWScreenSaverDisplayResolver alloc]
            initWithDisplayProvider:^NSArray<MWScreenSaverDisplay *> *{
                return displays;
            }];
        NSObject *attachedBuiltIn = [[NSObject alloc] init];
        NSObject *placeholderExternal = [[NSObject alloc] init];
        NSObject *wrongSizedPlaceholder = [[NSObject alloc] init];
        NSObject *visibleExternalA = [[NSObject alloc] init];
        NSObject *visibleExternalB = [[NSObject alloc] init];
        [delayedViewResolver beginAnimationForOwner:attachedBuiltIn atTime:20.0];
        Require([[delayedViewResolver displayIDForOwner:attachedBuiltIn
                                     preferredDisplayID:@"built-in"
                                               viewSize:NSMakeSize(1512, 982)] isEqualToString:@"built-in"],
                @"The attached built-in view should claim its exact display");
        [delayedViewResolver beginAnimationForOwner:placeholderExternal atTime:20.1];
        Require([[delayedViewResolver displayIDForOwner:placeholderExternal
                                     preferredDisplayID:nil
                                               viewSize:NSMakeSize(3440, 1440)] isEqualToString:@"external-a"],
                @"An early detached placeholder may provisionally claim a matching display");
        [delayedViewResolver beginAnimationForOwner:wrongSizedPlaceholder atTime:20.2];
        Require([delayedViewResolver displayIDForOwner:wrongSizedPlaceholder
                                    preferredDisplayID:nil
                                              viewSize:NSMakeSize(1512, 982)] == nil,
                @"A detached placeholder must never claim the sole unclaimed display when its size differs");

        [delayedViewResolver beginAnimationForOwner:visibleExternalA atTime:20.3];
        Require([[delayedViewResolver displayIDForOwner:visibleExternalA
                                     preferredDisplayID:nil
                                               viewSize:NSMakeSize(3440, 1440)] isEqualToString:@"external-b"],
                @"The first later external view should claim the remaining matching display");
        [delayedViewResolver beginAnimationForOwner:visibleExternalB atTime:20.4];
        Require([[delayedViewResolver displayIDForOwner:visibleExternalB
                                     preferredDisplayID:nil
                                               viewSize:NSMakeSize(3440, 1440)] isEqualToString:@"external-a"],
                @"The second later external view should replace the oldest detached placeholder");
        Require([delayedViewResolver displayIDForOwner:placeholderExternal
                                    preferredDisplayID:nil
                                              viewSize:NSMakeSize(3440, 1440)] == nil,
                @"A displaced older placeholder must not reclaim a display from newer visible views");

        TestReclaimedDisplaysAfterSessionReset(displays);
        printf("Screen saver display resolver tests passed.\n");
    }
    return 0;
}
