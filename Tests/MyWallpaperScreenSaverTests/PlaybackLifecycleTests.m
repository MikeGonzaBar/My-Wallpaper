#import <AVFoundation/AVFoundation.h>
#import <ScreenSaver/ScreenSaver.h>

#import "ScreenSaverDisplayResolver.h"
#import "ScreenSaverManifest.h"

@interface VideoScreenSaverView : ScreenSaverView
@property(nonatomic, strong) AVQueuePlayer *player;
@property(nonatomic, copy) NSArray<NSURL *> *orderedURLs;
@property(nonatomic, strong) NSMutableSet<NSValue *> *ownedItems;
@property(nonatomic, strong) NSMutableSet<NSURL *> *failedURLs;
@property(nonatomic) NSUInteger nextLoopIndex;
- (void)synchronizePlaybackForCurrentScreen;
- (nullable MWScreenSaverManifest *)loadManifest;
- (nullable NSString *)resolvedDisplayIDForCurrentView;
- (void)stopPlayback;
- (void)fillPlaybackQueue;
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
        Require(view.animationTimeInterval >= 1.0,
                @"AVPlayerLayer playback should not drive a high-frequency saver timer");
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

        VideoScreenSaverView *rollingView = [[VideoScreenSaverView alloc]
            initWithFrame:NSMakeRect(0, 0, 320, 180)
                isPreview:NO];
        NSURL *one = [NSURL fileURLWithPath:@"/one.mp4"];
        NSURL *two = [NSURL fileURLWithPath:@"/two.mp4"];
        NSURL *three = [NSURL fileURLWithPath:@"/three.mp4"];
        rollingView.player = [[AVQueuePlayer alloc] init];
        rollingView.orderedURLs = @[one, two, three];
        rollingView.ownedItems = [NSMutableSet set];
        rollingView.failedURLs = [NSMutableSet setWithObject:two];
        [rollingView fillPlaybackQueue];
        Require(rollingView.player.items.count == 2,
                @"Saver playback should retain only two AVPlayerItems");
        NSArray<NSURL *> *queuedURLs = [rollingView.player.items valueForKeyPath:@"asset.URL"];
        Require([queuedURLs isEqualToArray:@[one, three]],
                @"Saver playback should skip failed URLs when filling its rolling queue");
        [rollingView stopPlayback];
        printf("Screen saver playback lifecycle tests passed.\n");
    }
    return 0;
}
