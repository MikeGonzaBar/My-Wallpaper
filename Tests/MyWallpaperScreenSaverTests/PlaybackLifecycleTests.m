#import <ScreenSaver/ScreenSaver.h>

#import "ScreenSaverDisplayResolver.h"
#import "ScreenSaverManifest.h"

@interface VideoScreenSaverView : ScreenSaverView
- (void)synchronizePlaybackForCurrentScreen;
- (nullable MWScreenSaverManifest *)loadManifest;
- (nullable NSString *)resolvedDisplayIDForCurrentView;
- (void)stopPlayback;
@end

@interface TestVideoScreenSaverView : VideoScreenSaverView
@property(nonatomic, copy, nullable) NSString *testDisplayID;
@property(nonatomic) NSUInteger manifestLoadCount;
@property(nonatomic) NSUInteger stopPlaybackCount;
@end

@implementation TestVideoScreenSaverView

- (NSString *)resolvedDisplayIDForCurrentView {
    return self.testDisplayID;
}

- (MWScreenSaverManifest *)loadManifest {
    self.manifestLoadCount += 1;
    return nil;
}

- (void)stopPlayback {
    self.stopPlaybackCount += 1;
    [super stopPlayback];
}

@end

static void Require(BOOL condition, NSString *message) {
    if (!condition) {
        NSLog(@"FAILED: %@", message);
        exit(1);
    }
}

int main(void) {
    @autoreleasepool {
        TestVideoScreenSaverView *view = [[TestVideoScreenSaverView alloc]
            initWithFrame:NSMakeRect(0, 0, 800, 600)
                isPreview:NO];
        [view startAnimation];
        Require(view.manifestLoadCount == 0,
                @"Full-screen playback should wait until its display is known");

        view.testDisplayID = @"display";
        [view synchronizePlaybackForCurrentScreen];
        Require(view.manifestLoadCount == 1,
                @"Playback should resolve its manifest after a display becomes available");
        NSUInteger stopCountBeforeDisplacement = view.stopPlaybackCount;
        [NSNotificationCenter.defaultCenter
            postNotificationName:MWScreenSaverDisplayClaimWasDisplacedNotification
                          object:view];
        Require(view.stopPlaybackCount == stopCountBeforeDisplacement + 1,
                @"A displaced view should immediately stop any hidden playback");
        [view stopAnimation];

        TestVideoScreenSaverView *preview = [[TestVideoScreenSaverView alloc]
            initWithFrame:NSMakeRect(0, 0, 320, 180)
                isPreview:YES];
        [preview startAnimation];
        Require(preview.manifestLoadCount == 1,
                @"System Settings preview should use the fallback without a display window");
        [preview stopAnimation];
        printf("Screen saver playback lifecycle tests passed.\n");
    }
    return 0;
}
