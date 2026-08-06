#import <ScreenSaver/ScreenSaver.h>

#import "ScreenSaverManifest.h"

@interface VideoScreenSaverView : ScreenSaverView
- (void)synchronizePlaybackForCurrentScreen;
- (nullable MWScreenSaverManifest *)loadManifest;
- (nullable NSString *)resolvedDisplayIDForCurrentView;
@end

@interface TestVideoScreenSaverView : VideoScreenSaverView
@property(nonatomic, copy, nullable) NSString *testDisplayID;
@property(nonatomic) NSUInteger manifestLoadCount;
@end

@implementation TestVideoScreenSaverView

- (NSString *)resolvedDisplayIDForCurrentView {
    return self.testDisplayID;
}

- (MWScreenSaverManifest *)loadManifest {
    self.manifestLoadCount += 1;
    return nil;
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
