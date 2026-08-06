#import "ScreenSaverDisplayResolver.h"
#import "ScreenSaverDiagnostics.h"

#import <CoreGraphics/CoreGraphics.h>
#import <math.h>

NSNotificationName const MWScreenSaverDisplayClaimsDidResetNotification =
    @"MWScreenSaverDisplayClaimsDidResetNotification";

static const NSTimeInterval MWAnimationSessionGap = 2.0;

@implementation MWScreenSaverDisplay

- (instancetype)initWithDisplayID:(NSString *)displayID size:(NSSize)size {
    self = [super init];
    if (self) {
        _displayID = [displayID copy];
        _size = size;
    }
    return self;
}

@end

@interface MWScreenSaverDisplayResolver ()
@property(nonatomic, copy) MWScreenSaverDisplayProvider displayProvider;
@property(nonatomic, strong) NSMapTable<id, NSString *> *assignments;
@property(nonatomic, strong) NSLock *lock;
@property(nonatomic) NSTimeInterval lastAnimationStartTime;
@property(nonatomic) NSUInteger animationSession;
@end

@implementation MWScreenSaverDisplayResolver

+ (instancetype)sharedResolver {
    static MWScreenSaverDisplayResolver *resolver;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        resolver = [[MWScreenSaverDisplayResolver alloc]
            initWithDisplayProvider:^NSArray<MWScreenSaverDisplay *> *{
            return [MWScreenSaverDisplayResolver onlineDisplays];
        }];
    });
    return resolver;
}

- (instancetype)initWithDisplayProvider:(MWScreenSaverDisplayProvider)displayProvider {
    self = [super init];
    if (self) {
        _displayProvider = [displayProvider copy];
        _assignments = [NSMapTable weakToStrongObjectsMapTable];
        _lock = [[NSLock alloc] init];
    }
    return self;
}

- (void)beginAnimationForOwner:(id)owner {
    [self beginAnimationForOwner:owner
                          atTime:NSProcessInfo.processInfo.systemUptime];
}

- (void)beginAnimationForOwner:(id)owner atTime:(NSTimeInterval)startTime {
    if (!owner) {
        return;
    }

    BOOL didReset = NO;
    NSUInteger releasedClaims = 0;
    NSUInteger session = 0;
    [self.lock lock];
    NSTimeInterval gap = startTime - self.lastAnimationStartTime;
    if (self.lastAnimationStartTime == 0 || gap > MWAnimationSessionGap) {
        releasedClaims = self.assignments.count;
        [self.assignments removeAllObjects];
        self.animationSession += 1;
        didReset = YES;
    }
    self.lastAnimationStartTime = startTime;
    session = self.animationSession;
    [self.lock unlock];

    os_log_with_type(MWScreenSaverDiagnosticLog(), OS_LOG_TYPE_DEFAULT,
        "animation-session owner=%{public}p session=%{public}lu action=%{public}s releasedClaims=%{public}lu",
        (__bridge void *)owner,
        (unsigned long)session,
        didReset ? "reset" : "join",
        (unsigned long)releasedClaims);

    if (didReset) {
        [NSNotificationCenter.defaultCenter
            postNotificationName:MWScreenSaverDisplayClaimsDidResetNotification
                          object:owner];
    }
}

- (NSString *)displayIDForOwner:(id)owner
                          screen:(NSScreen *)screen
                        viewSize:(NSSize)viewSize {
    NSString *preferredID = [self.class stableIdentifierForScreen:screen];
    return [self displayIDForOwner:owner
                preferredDisplayID:preferredID
                          viewSize:viewSize];
}

- (NSString *)displayIDForOwner:(id)owner
             preferredDisplayID:(NSString *)preferredID
                       viewSize:(NSSize)viewSize {
    if (!owner) {
        return nil;
    }

    NSArray<MWScreenSaverDisplay *> *displays = self.displayProvider();

    NSMutableArray<NSString *> *candidateSummaries = [NSMutableArray array];
    for (MWScreenSaverDisplay *display in displays) {
        [candidateSummaries addObject:[NSString stringWithFormat:@"%@=%.0fx%.0f",
            display.displayID,
            display.size.width,
            display.size.height]];
    }
    os_log_with_type(MWScreenSaverDiagnosticLog(), OS_LOG_TYPE_DEFAULT,
        "resolve owner=%{public}p view=%{public}.0fx%{public}.0f screenAttached=%{public}s preferred=%{public}@ candidates=%{public}@",
        (__bridge void *)owner,
        viewSize.width,
        viewSize.height,
        preferredID.length > 0 ? "yes" : "no",
        preferredID ?: @"none",
        [candidateSummaries componentsJoinedByString:@","]);

    [self.lock lock];
    @try {
        NSString *existingID = [self.assignments objectForKey:owner];
        if (preferredID.length > 0 &&
            [self displayWithID:preferredID inDisplays:displays]) {
            id previousOwner = [self ownerAssignedToDisplayID:preferredID excludingOwner:owner];
            if (previousOwner) {
                [self.assignments removeObjectForKey:previousOwner];
            }
            [self.assignments setObject:preferredID forKey:owner];
            os_log_with_type(MWScreenSaverDiagnosticLog(), OS_LOG_TYPE_DEFAULT,
                "route owner=%{public}p display=%{public}@ reason=%{public}s previousOwner=%{public}p",
                (__bridge void *)owner,
                preferredID,
                previousOwner ? "attached-screen-takeover" : "attached-screen",
                (__bridge void *)previousOwner);
            return preferredID;
        }

        MWScreenSaverDisplay *existing = [self displayWithID:existingID inDisplays:displays];
        if (existing && [self size:existing.size matchesSize:viewSize]) {
            os_log_with_type(MWScreenSaverDiagnosticLog(), OS_LOG_TYPE_DEFAULT,
                "route owner=%{public}p display=%{public}@ reason=existing-claim",
                (__bridge void *)owner,
                existingID);
            return existingID;
        }
        [self.assignments removeObjectForKey:owner];

        for (MWScreenSaverDisplay *display in displays) {
            if ([self size:display.size matchesSize:viewSize] &&
                [self displayID:display.displayID isAvailableToOwner:owner]) {
                [self.assignments setObject:display.displayID forKey:owner];
                os_log_with_type(MWScreenSaverDiagnosticLog(), OS_LOG_TYPE_DEFAULT,
                    "route owner=%{public}p display=%{public}@ reason=matching-dimensions",
                    (__bridge void *)owner,
                    display.displayID);
                return display.displayID;
            }
        }

        NSMutableArray<MWScreenSaverDisplay *> *available = [NSMutableArray array];
        for (MWScreenSaverDisplay *display in displays) {
            if ([self displayID:display.displayID isAvailableToOwner:owner]) {
                [available addObject:display];
            }
        }
        if (available.count == 1) {
            NSString *displayID = available.firstObject.displayID;
            [self.assignments setObject:displayID forKey:owner];
            os_log_with_type(MWScreenSaverDiagnosticLog(), OS_LOG_TYPE_DEFAULT,
                "route owner=%{public}p display=%{public}@ reason=only-unclaimed-display",
                (__bridge void *)owner,
                displayID);
            return displayID;
        }
        os_log_with_type(MWScreenSaverDiagnosticLog(), OS_LOG_TYPE_ERROR,
            "route owner=%{public}p display=none reason=ambiguous-or-no-match available=%{public}lu",
            (__bridge void *)owner,
            (unsigned long)available.count);
        return nil;
    } @finally {
        [self.lock unlock];
    }
}

- (id)ownerAssignedToDisplayID:(NSString *)displayID excludingOwner:(id)owner {
    for (id existingOwner in self.assignments) {
        NSString *assignedID = [self.assignments objectForKey:existingOwner];
        if (existingOwner != owner && [assignedID isEqualToString:displayID]) {
            return existingOwner;
        }
    }
    return nil;
}

- (void)releaseDisplayForOwner:(id)owner {
    if (!owner) {
        return;
    }
    [self.lock lock];
    NSString *displayID = [self.assignments objectForKey:owner];
    [self.assignments removeObjectForKey:owner];
    [self.lock unlock];
    os_log_with_type(MWScreenSaverDiagnosticLog(), OS_LOG_TYPE_DEFAULT,
        "release owner=%{public}p display=%{public}@",
        (__bridge void *)owner,
        displayID ?: @"none");
}

- (MWScreenSaverDisplay *)displayWithID:(NSString *)displayID
                             inDisplays:(NSArray<MWScreenSaverDisplay *> *)displays {
    if (displayID.length == 0) {
        return nil;
    }
    for (MWScreenSaverDisplay *display in displays) {
        if ([display.displayID isEqualToString:displayID]) {
            return display;
        }
    }
    return nil;
}

- (BOOL)displayID:(NSString *)displayID isAvailableToOwner:(id)owner {
    for (id existingOwner in self.assignments) {
        NSString *assignedID = [self.assignments objectForKey:existingOwner];
        if (existingOwner != owner && [assignedID isEqualToString:displayID]) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)size:(NSSize)first matchesSize:(NSSize)second {
    return first.width > 0 && first.height > 0 &&
        fabs(first.width - second.width) <= 1.0 &&
        fabs(first.height - second.height) <= 1.0;
}

+ (NSArray<MWScreenSaverDisplay *> *)onlineDisplays {
    uint32_t count = 0;
    if (CGGetOnlineDisplayList(0, NULL, &count) != kCGErrorSuccess || count == 0) {
        return @[];
    }

    NSMutableData *storage = [NSMutableData dataWithLength:sizeof(CGDirectDisplayID) * count];
    CGDirectDisplayID *displayIDs = storage.mutableBytes;
    if (CGGetOnlineDisplayList(count, displayIDs, &count) != kCGErrorSuccess) {
        return @[];
    }

    NSMutableArray<MWScreenSaverDisplay *> *result = [NSMutableArray arrayWithCapacity:count];
    for (uint32_t index = 0; index < count; index += 1) {
        NSString *displayID = [self stableIdentifierForDisplayID:displayIDs[index]];
        if (displayID.length == 0) {
            continue;
        }
        CGRect bounds = CGDisplayBounds(displayIDs[index]);
        [result addObject:[[MWScreenSaverDisplay alloc]
            initWithDisplayID:displayID
                         size:NSMakeSize(bounds.size.width, bounds.size.height)]];
    }
    return result;
}

+ (NSString *)stableIdentifierForScreen:(NSScreen *)screen {
    NSNumber *screenNumber = screen.deviceDescription[@"NSScreenNumber"];
    if (!screenNumber) {
        return nil;
    }
    return [self stableIdentifierForDisplayID:screenNumber.unsignedIntValue];
}

+ (NSString *)stableIdentifierForDisplayID:(CGDirectDisplayID)displayID {
    CFUUIDRef UUID = CGDisplayCreateUUIDFromDisplayID(displayID);
    if (!UUID) {
        return nil;
    }
    CFStringRef UUIDString = CFUUIDCreateString(kCFAllocatorDefault, UUID);
    NSString *identifier = [(__bridge NSString *)UUIDString copy];
    CFRelease(UUIDString);
    CFRelease(UUID);
    return identifier;
}

@end
