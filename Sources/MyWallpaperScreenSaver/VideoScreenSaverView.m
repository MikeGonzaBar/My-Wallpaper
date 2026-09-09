#import <AVFoundation/AVFoundation.h>
#import <ScreenSaver/ScreenSaver.h>

#import "ScreenSaverDisplayResolver.h"
#import "ScreenSaverDiagnostics.h"
#import "ScreenSaverManifest.h"

static NSString *MWViewFingerprint(id view) {
    if (!view) {
        return @"unavailable";
    }
    return MWDiagnosticFingerprintForString(
        [NSString stringWithFormat:@"%p", (__bridge void *)view]);
}

static NSString *MWDisplayFingerprint(NSString *displayID) {
    return displayID.length > 0
        ? MWDiagnosticFingerprintForString(displayID)
        : @"none";
}

@interface VideoScreenSaverView : ScreenSaverView
@property(nonatomic, strong) AVQueuePlayer *player;
@property(nonatomic, strong) AVPlayerLayer *playerLayer;
@property(nonatomic, copy) NSArray<NSURL *> *orderedURLs;
@property(nonatomic, strong) NSMutableSet<NSValue *> *ownedItems;
@property(nonatomic, strong) NSMutableSet<NSURL *> *failedURLs;
@property(nonatomic, copy) NSString *activeDisplayID;
@property(nonatomic) NSUInteger nextLoopIndex;
@property(nonatomic, strong) id completionObserver;
@property(nonatomic, strong) id failureObserver;
@property(nonatomic, strong) id accessLogObserver;
@property(nonatomic, strong) NSMutableSet<NSURL *> *loggedPlayingURLs;
@property(nonatomic, weak) NSWindow *observedWindow;
@property(nonatomic, strong) id screenObserver;
@property(nonatomic, strong) id claimsResetObserver;
@property(nonatomic, strong) id displacedClaimObserver;
@property(nonatomic) NSUInteger playbackProbeGeneration;
@property(nonatomic, copy) NSString *diagnosticOwnerFingerprint;
@end

@implementation VideoScreenSaverView

- (instancetype)initWithFrame:(NSRect)frame isPreview:(BOOL)isPreview {
    self = [super initWithFrame:frame isPreview:isPreview];
    if (self) {
        self.diagnosticOwnerFingerprint = MWViewFingerprint(self);
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.blackColor.CGColor;
        // AVPlayerLayer drives video frames. Keep ScreenSaverView's otherwise-unused
        // animation callback dormant to avoid continuous timer wakeups.
        self.animationTimeInterval = 60.0;
        os_log_with_type(MWScreenSaverDiagnosticLog(), OS_LOG_TYPE_DEFAULT,
            "view-init owner=%{public}@ preview=%{public}s frame=%{public}.0fx%{public}.0f",
            self.diagnosticOwnerFingerprint,
            isPreview ? "yes" : "no",
            frame.size.width,
            frame.size.height);
        __weak typeof(self) weakSelf = self;
        self.claimsResetObserver = [NSNotificationCenter.defaultCenter
            addObserverForName:MWScreenSaverDisplayClaimsDidResetNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(NSNotification *notification) {
                        if (notification.object != weakSelf) {
                            [weakSelf stopPlayback];
                        }
                    }];
        self.displacedClaimObserver = [NSNotificationCenter.defaultCenter
            addObserverForName:MWScreenSaverDisplayClaimWasDisplacedNotification
                        object:self
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(__unused NSNotification *notification) {
                        [weakSelf stopPlayback];
                    }];
    }
    return self;
}

- (void)startAnimation {
    [super startAnimation];
    [[MWScreenSaverDisplayResolver sharedResolver] beginAnimationForOwner:self];
    os_log_with_type(MWScreenSaverDiagnosticLog(), OS_LOG_TYPE_DEFAULT,
        "view-start owner=%{public}@ preview=%{public}s bounds=%{public}.0fx%{public}.0f window=%{public}s screen=%{public}s",
        self.diagnosticOwnerFingerprint,
        self.isPreview ? "yes" : "no",
        self.bounds.size.width,
        self.bounds.size.height,
        self.window ? "yes" : "no",
        self.window.screen ? "yes" : "no");
    [self stopPlayback];
    [self observeCurrentWindow];
    [self synchronizePlaybackForCurrentScreen];
}

- (void)stopAnimation {
    os_log_with_type(MWScreenSaverDiagnosticLog(), OS_LOG_TYPE_DEFAULT,
        "view-stop owner=%{public}@ display=%{public}@",
        self.diagnosticOwnerFingerprint,
        MWDisplayFingerprint(self.activeDisplayID));
    [self removeScreenObserver];
    [self stopPlayback];
    [[MWScreenSaverDisplayResolver sharedResolver] releaseDisplayForOwner:self];
    [super stopAnimation];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.isAnimating) {
        [self observeCurrentWindow];
        [self synchronizePlaybackForCurrentScreen];
    }
}

- (void)synchronizePlaybackForCurrentScreen {
    NSString *displayID = nil;
    if (self.isPreview) {
        displayID = @"preview";
    } else {
        displayID = [self resolvedDisplayIDForCurrentView];
        if (displayID.length == 0) {
            // Detached remote views can arrive before their final dimensions.
            // Wait for layout or a window screen update instead of sending every
            // display to the manifest fallback.
            [self stopPlayback];
            os_log_with_type(MWScreenSaverDiagnosticLog(), OS_LOG_TYPE_ERROR,
                "playback-wait owner=%{public}@ reason=display-unresolved bounds=%{public}.0fx%{public}.0f",
                self.diagnosticOwnerFingerprint,
                self.bounds.size.width,
                self.bounds.size.height);
            return;
        }
    }

    if (self.player && [self.activeDisplayID isEqualToString:displayID]) {
        return;
    }
    [self stopPlayback];

    MWScreenSaverManifest *manifest = [self loadManifest];
    if (!manifest) {
        os_log_with_type(MWScreenSaverDiagnosticLog(), OS_LOG_TYPE_ERROR,
            "playback-abort owner=%{public}@ display=%{public}@ reason=manifest-unavailable",
            self.diagnosticOwnerFingerprint,
            MWDisplayFingerprint(displayID));
        return;
    }
    NSArray<NSURL *> *URLs = [manifest
        videoURLsForDisplayID:self.isPreview ? nil : displayID
                       preview:self.isPreview];
    if (URLs.count == 0) {
        os_log_with_type(MWScreenSaverDiagnosticLog(), OS_LOG_TYPE_ERROR,
            "playback-abort owner=%{public}@ display=%{public}@ reason=no-playable-videos",
            self.diagnosticOwnerFingerprint,
            MWDisplayFingerprint(displayID));
        return;
    }

    NSMutableArray<NSString *> *fingerprints = [NSMutableArray arrayWithCapacity:URLs.count];
    for (NSURL *URL in URLs) {
        [fingerprints addObject:MWVideoFingerprint(URL)];
    }
    os_log_with_type(MWScreenSaverDiagnosticLog(), OS_LOG_TYPE_DEFAULT,
        "playback-plan owner=%{public}@ display=%{public}@ videos=%{public}lu order=%{public}@ muted=%{public}s scaling=%{public}@",
        self.diagnosticOwnerFingerprint,
        MWDisplayFingerprint(displayID),
        (unsigned long)URLs.count,
        [fingerprints componentsJoinedByString:@","],
        manifest.isMuted ? "yes" : "no",
        manifest.scaling);

    self.activeDisplayID = displayID;
    self.orderedURLs = URLs;
    self.nextLoopIndex = 0;
    self.ownedItems = [NSMutableSet set];
    self.failedURLs = [NSMutableSet set];
    self.loggedPlayingURLs = [NSMutableSet set];
    self.player = [[AVQueuePlayer alloc] init];
    self.player.muted = manifest.isMuted;
    [self fillPlaybackQueue];

    self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
    self.playerLayer.videoGravity = [manifest.scaling isEqualToString:@"fit"]
        ? AVLayerVideoGravityResizeAspect
        : AVLayerVideoGravityResizeAspectFill;
    self.playerLayer.frame = self.bounds;
    [self.layer addSublayer:self.playerLayer];

    __weak typeof(self) weakSelf = self;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    self.completionObserver = [center
        addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                    object:nil
                     queue:NSOperationQueue.mainQueue
                usingBlock:^(NSNotification *notification) {
                    [weakSelf playerItemDidFinish:notification.object];
                }];
    self.failureObserver = [center
        addObserverForName:AVPlayerItemFailedToPlayToEndTimeNotification
                    object:nil
                     queue:NSOperationQueue.mainQueue
                usingBlock:^(NSNotification *notification) {
                    [weakSelf playerItemDidFail:notification.object];
                }];
    self.accessLogObserver = [center
        addObserverForName:AVPlayerItemNewAccessLogEntryNotification
                    object:nil
                     queue:NSOperationQueue.mainQueue
                usingBlock:^(NSNotification *notification) {
                    [weakSelf playerItemDidBeginPlayback:notification.object];
                }];
    [self.player play];
    os_log_with_type(MWScreenSaverDiagnosticLog(), OS_LOG_TYPE_DEFAULT,
        "playback-start-requested owner=%{public}@ display=%{public}@ queued=%{public}lu",
        self.diagnosticOwnerFingerprint,
        MWDisplayFingerprint(displayID),
        (unsigned long)self.ownedItems.count);
    [self schedulePlaybackProbeAfter:2.0 label:@"2s"];
    [self schedulePlaybackProbeAfter:8.0 label:@"8s"];
}

- (NSString *)resolvedDisplayIDForCurrentView {
    return [[MWScreenSaverDisplayResolver sharedResolver]
        displayIDForOwner:self
                   screen:self.window.screen
                 viewSize:self.bounds.size];
}

- (MWScreenSaverManifest *)loadManifest {
    return [MWScreenSaverManifest loadFromApplicationSupport];
}

- (void)layout {
    [super layout];
    os_log_with_type(MWScreenSaverDiagnosticLog(), OS_LOG_TYPE_DEFAULT,
        "view-layout owner=%{public}@ bounds=%{public}.0fx%{public}.0f player=%{public}s window=%{public}s screen=%{public}s",
        self.diagnosticOwnerFingerprint,
        self.bounds.size.width,
        self.bounds.size.height,
        self.player ? "yes" : "no",
        self.window ? "yes" : "no",
        self.window.screen ? "yes" : "no");
    self.playerLayer.frame = self.bounds;
    if (self.isAnimating && !self.player) {
        [self synchronizePlaybackForCurrentScreen];
    }
}

- (void)dealloc {
    if (self.claimsResetObserver) {
        [NSNotificationCenter.defaultCenter removeObserver:self.claimsResetObserver];
    }
    if (self.displacedClaimObserver) {
        [NSNotificationCenter.defaultCenter removeObserver:self.displacedClaimObserver];
    }
    [self removeScreenObserver];
    [self stopPlayback];
    [[MWScreenSaverDisplayResolver sharedResolver] releaseDisplayForOwner:self];
}

- (void)observeCurrentWindow {
    NSWindow *window = self.window;
    if (self.observedWindow == window && self.screenObserver) {
        return;
    }
    [self removeScreenObserver];
    self.observedWindow = window;
    if (!window) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    self.screenObserver = [NSNotificationCenter.defaultCenter
        addObserverForName:NSWindowDidChangeScreenNotification
                    object:window
                     queue:NSOperationQueue.mainQueue
                usingBlock:^(__unused NSNotification *notification) {
                    [weakSelf synchronizePlaybackForCurrentScreen];
                }];
}

- (void)removeScreenObserver {
    if (self.screenObserver) {
        [NSNotificationCenter.defaultCenter removeObserver:self.screenObserver];
        self.screenObserver = nil;
    }
    self.observedWindow = nil;
}

- (void)stopPlayback {
    self.playbackProbeGeneration += 1;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    if (self.completionObserver) {
        [center removeObserver:self.completionObserver];
        self.completionObserver = nil;
    }
    if (self.failureObserver) {
        [center removeObserver:self.failureObserver];
        self.failureObserver = nil;
    }
    if (self.accessLogObserver) {
        [center removeObserver:self.accessLogObserver];
        self.accessLogObserver = nil;
    }
    [self.player pause];
    [self.player removeAllItems];
    self.playerLayer.player = nil;
    [self.playerLayer removeFromSuperlayer];
    self.playerLayer = nil;
    self.player = nil;
    self.activeDisplayID = nil;
    self.orderedURLs = @[];
    self.ownedItems = nil;
    self.failedURLs = nil;
    self.loggedPlayingURLs = nil;
    self.nextLoopIndex = 0;
}

- (void)schedulePlaybackProbeAfter:(NSTimeInterval)delay label:(NSString *)label {
    NSUInteger generation = self.playbackProbeGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.player ||
            strongSelf.playbackProbeGeneration != generation) {
            return;
        }

        AVPlayerItem *item = strongSelf.player.currentItem;
        NSError *error = item.error;
        AVPlayerItemAccessLogEvent *accessEvent = item.accessLog.events.lastObject;
        NSInteger droppedFrames = accessEvent ? accessEvent.numberOfDroppedVideoFrames : -1;
        NSInteger stalls = accessEvent ? accessEvent.numberOfStalls : -1;
        double startupTime = accessEvent ? accessEvent.startupTime : -1;
        double videoBitRate = accessEvent ? accessEvent.averageVideoBitrate : -1;
        os_log_with_type(MWScreenSaverDiagnosticLog(),
                         error ? OS_LOG_TYPE_ERROR : OS_LOG_TYPE_DEFAULT,
            "playback-probe owner=%{public}@ display=%{public}@ after=%{public}@ playerStatus=%{public}ld itemStatus=%{public}ld rate=%{public}.2f dropped=%{public}ld stalls=%{public}ld startup=%{public}.3f bitrate=%{public}.0f errorDomain=%{public}@ errorCode=%{public}ld",
            strongSelf.diagnosticOwnerFingerprint,
            MWDisplayFingerprint(strongSelf.activeDisplayID),
            label,
            (long)strongSelf.player.timeControlStatus,
            (long)item.status,
            strongSelf.player.rate,
            (long)droppedFrames,
            (long)stalls,
            startupTime,
            videoBitRate,
            error.domain ?: @"none",
            (long)error.code);
    });
}

- (void)playerItemDidFinish:(id)object {
    AVPlayerItem *endedItem = [object isKindOfClass:AVPlayerItem.class] ? object : nil;
    if (![self removeOwnedItem:endedItem]) {
        return;
    }
    [self fillPlaybackQueue];
}

- (void)playerItemDidFail:(id)object {
    AVPlayerItem *failedItem = [object isKindOfClass:AVPlayerItem.class] ? object : nil;
    if (![self removeOwnedItem:failedItem]) {
        return;
    }
    if ([failedItem.asset isKindOfClass:AVURLAsset.class]) {
        NSURL *URL = ((AVURLAsset *)failedItem.asset).URL;
        [self.failedURLs addObject:URL];
        os_log_with_type(MWScreenSaverDiagnosticLog(), OS_LOG_TYPE_ERROR,
            "playback-failed owner=%{public}@ display=%{public}@ video=%{public}@",
            self.diagnosticOwnerFingerprint,
            MWDisplayFingerprint(self.activeDisplayID),
            MWVideoFingerprint(URL));
    }
    BOOL hasPlayableURL = NO;
    for (NSURL *URL in self.orderedURLs) {
        if (![self.failedURLs containsObject:URL]) {
            hasPlayableURL = YES;
            break;
        }
    }
    if (!hasPlayableURL) {
        [self.player pause];
    } else {
        [self fillPlaybackQueue];
    }
}

- (void)playerItemDidBeginPlayback:(id)object {
    AVPlayerItem *item = [object isKindOfClass:AVPlayerItem.class] ? object : nil;
    NSValue *identity = item ? [NSValue valueWithNonretainedObject:item] : nil;
    if (!identity || ![self.ownedItems containsObject:identity] ||
        ![item.asset isKindOfClass:AVURLAsset.class]) {
        return;
    }

    NSURL *URL = ((AVURLAsset *)item.asset).URL;
    if ([self.loggedPlayingURLs containsObject:URL]) {
        return;
    }
    [self.loggedPlayingURLs addObject:URL];
    os_log_with_type(MWScreenSaverDiagnosticLog(), OS_LOG_TYPE_DEFAULT,
        "playback-active owner=%{public}@ display=%{public}@ video=%{public}@",
        self.diagnosticOwnerFingerprint,
        MWDisplayFingerprint(self.activeDisplayID),
        MWVideoFingerprint(URL));
}

- (BOOL)removeOwnedItem:(AVPlayerItem *)item {
    if (!item) {
        return NO;
    }
    NSValue *identity = [NSValue valueWithNonretainedObject:item];
    if (![self.ownedItems containsObject:identity]) {
        return NO;
    }
    [self.ownedItems removeObject:identity];
    return YES;
}

- (NSURL *)nextPlayableLoopURL {
    if (self.orderedURLs.count == 0 || self.failedURLs.count >= self.orderedURLs.count) {
        return nil;
    }
    for (NSUInteger attempt = 0; attempt < self.orderedURLs.count; attempt += 1) {
        NSURL *URL = self.orderedURLs[self.nextLoopIndex];
        self.nextLoopIndex = (self.nextLoopIndex + 1) % self.orderedURLs.count;
        if (![self.failedURLs containsObject:URL]) {
            return URL;
        }
    }
    return nil;
}

- (void)fillPlaybackQueue {
    NSUInteger playableURLCount = 0;
    for (NSURL *URL in [NSSet setWithArray:self.orderedURLs]) {
        if (![self.failedURLs containsObject:URL]) {
            playableURLCount += 1;
        }
    }
    NSUInteger targetCount = MIN((NSUInteger)2, playableURLCount);
    while (self.ownedItems.count < targetCount) {
        NSURL *nextURL = [self nextPlayableLoopURL];
        if (!nextURL) {
            break;
        }
        [self enqueueURL:nextURL];
    }
}

- (void)enqueueURL:(NSURL *)URL {
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:URL];
    [self.ownedItems addObject:[NSValue valueWithNonretainedObject:item]];
    [self.player insertItem:item afterItem:nil];
}

@end
