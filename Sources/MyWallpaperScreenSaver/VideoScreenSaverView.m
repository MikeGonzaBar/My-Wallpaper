#import <AVFoundation/AVFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ScreenSaver/ScreenSaver.h>

@interface VideoScreenSaverView : ScreenSaverView
@property(nonatomic, strong) AVQueuePlayer *player;
@property(nonatomic, strong) AVPlayerLayer *playerLayer;
@property(nonatomic, copy) NSArray<NSURL *> *orderedURLs;
@property(nonatomic, strong) NSMutableSet<NSValue *> *ownedItems;
@property(nonatomic) NSUInteger nextLoopIndex;
@end

@implementation VideoScreenSaverView

- (instancetype)initWithFrame:(NSRect)frame isPreview:(BOOL)isPreview {
    self = [super initWithFrame:frame isPreview:isPreview];
    if (self) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.blackColor.CGColor;
        self.animationTimeInterval = 1.0 / 30.0;
    }
    return self;
}

- (void)startAnimation {
    [super startAnimation];
    [self stopPlayback];

    NSDictionary *settings = [self loadSettings];
    NSDictionary *configuration = [self configurationForCurrentDisplayFromSettings:settings];
    NSArray<NSURL *> *urls = [self orderedVideoURLsForConfiguration:configuration settings:settings];
    if (urls.count == 0) {
        return;
    }

    self.orderedURLs = urls;
    self.nextLoopIndex = 0;
    self.ownedItems = [NSMutableSet set];
    self.player = [[AVQueuePlayer alloc] init];
    self.player.muted = [settings[@"isMuted"] boolValue];

    for (NSURL *url in urls) {
        [self enqueueURL:url];
    }

    self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
    NSString *scaling = settings[@"scaling"];
    self.playerLayer.videoGravity = [scaling isEqualToString:@"Fit to screen"]
        ? AVLayerVideoGravityResizeAspect
        : AVLayerVideoGravityResizeAspectFill;
    self.playerLayer.frame = self.bounds;
    [self.layer addSublayer:self.playerLayer];

    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(playerItemDidFinish:)
               name:AVPlayerItemDidPlayToEndTimeNotification
             object:nil];
    [self.player play];
}

- (void)stopAnimation {
    [self stopPlayback];
    [super stopAnimation];
}

- (void)layout {
    [super layout];
    self.playerLayer.frame = self.bounds;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)stopPlayback {
    [[NSNotificationCenter defaultCenter]
        removeObserver:self
                  name:AVPlayerItemDidPlayToEndTimeNotification
                object:nil];
    [self.player pause];
    [self.player removeAllItems];
    self.playerLayer.player = nil;
    [self.playerLayer removeFromSuperlayer];
    self.playerLayer = nil;
    self.player = nil;
    self.orderedURLs = @[];
    self.ownedItems = nil;
}

- (void)playerItemDidFinish:(NSNotification *)notification {
    AVPlayerItem *endedItem = notification.object;
    if (![endedItem isKindOfClass:AVPlayerItem.class] || self.orderedURLs.count == 0) {
        return;
    }

    NSValue *identity = [NSValue valueWithNonretainedObject:endedItem];
    if (![self.ownedItems containsObject:identity]) {
        return;
    }
    [self.ownedItems removeObject:identity];

    NSURL *nextURL = self.orderedURLs[self.nextLoopIndex];
    self.nextLoopIndex = (self.nextLoopIndex + 1) % self.orderedURLs.count;
    [self enqueueURL:nextURL];
}

- (void)enqueueURL:(NSURL *)url {
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
    [self.ownedItems addObject:[NSValue valueWithNonretainedObject:item]];
    [self.player insertItem:item afterItem:nil];
}

- (NSDictionary *)loadSettings {
    NSArray<NSString *> *directories = NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory,
        NSUserDomainMask,
        YES
    );
    NSString *settingsPath = [[directories.firstObject
        stringByAppendingPathComponent:@"My Wallpaper"]
        stringByAppendingPathComponent:@"settings.json"];
    NSData *data = [NSData dataWithContentsOfFile:settingsPath];
    if (!data) {
        return @{};
    }

    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [json isKindOfClass:NSDictionary.class] ? json : @{};
}

- (NSDictionary *)configurationForCurrentDisplayFromSettings:(NSDictionary *)settings {
    NSArray *configurations = settings[@"screens"];
    if (![configurations isKindOfClass:NSArray.class]) {
        return nil;
    }

    if (self.isPreview) {
        return configurations.firstObject;
    }

    NSString *displayID = [self stableIdentifierForScreen:self.window.screen];
    for (NSDictionary *configuration in configurations) {
        if ([configuration[@"screenID"] isEqualToString:displayID]) {
            return configuration;
        }
    }
    return nil;
}

- (NSArray<NSURL *> *)orderedVideoURLsForConfiguration:(NSDictionary *)configuration
                                              settings:(NSDictionary *)settings {
    if (![configuration isKindOfClass:NSDictionary.class]) {
        return @[];
    }

    NSMutableDictionary<NSString *, NSString *> *pathsByID = [NSMutableDictionary dictionary];
    for (NSDictionary *video in settings[@"videos"]) {
        NSString *videoID = video[@"id"];
        NSString *path = video[@"path"];
        if (videoID.length > 0 && path.length > 0) {
            pathsByID[videoID] = path;
        }
    }

    NSArray<NSString *> *videoIDs = configuration[@"videoIDs"];
    if (![videoIDs isKindOfClass:NSArray.class]) {
        return @[];
    }

    NSMutableArray<NSString *> *playableIDs = [NSMutableArray array];
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    for (NSString *videoID in videoIDs) {
        NSString *path = pathsByID[videoID];
        if (path && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [playableIDs addObject:videoID];
            [urls addObject:[NSURL fileURLWithPath:path]];
        }
    }
    if (urls.count == 0) {
        return @[];
    }

    if ([configuration[@"mode"] isEqualToString:@"Single video"]) {
        NSString *startVideoID = configuration[@"startVideoID"];
        NSUInteger selectedIndex = [playableIDs indexOfObject:startVideoID];
        return @[urls[selectedIndex == NSNotFound ? 0 : selectedIndex]];
    }

    NSString *startVideoID = configuration[@"startVideoID"];
    NSUInteger startIndex = [playableIDs indexOfObject:startVideoID];
    if (startIndex == NSNotFound || startIndex == 0) {
        return urls;
    }

    NSRange tailRange = NSMakeRange(startIndex, urls.count - startIndex);
    NSRange headRange = NSMakeRange(0, startIndex);
    return [[urls subarrayWithRange:tailRange]
        arrayByAddingObjectsFromArray:[urls subarrayWithRange:headRange]];
}

- (NSString *)stableIdentifierForScreen:(NSScreen *)screen {
    NSNumber *screenNumber = screen.deviceDescription[@"NSScreenNumber"];
    if (!screenNumber) {
        return screen.localizedName;
    }

    CGDirectDisplayID displayID = screenNumber.unsignedIntValue;
    CFUUIDRef uuid = CGDisplayCreateUUIDFromDisplayID(displayID);
    if (!uuid) {
        return screenNumber.stringValue;
    }
    CFStringRef uuidString = CFUUIDCreateString(kCFAllocatorDefault, uuid);
    NSString *identifier = [(__bridge NSString *)uuidString copy];
    CFRelease(uuidString);
    CFRelease(uuid);
    return identifier;
}

@end
