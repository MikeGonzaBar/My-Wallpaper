#import "ScreenSaverDisplayResolver.h"
#import "ScreenSaverDiagnostics.h"

#import <CoreGraphics/CoreGraphics.h>
#import <math.h>

NSNotificationName const MWScreenSaverDisplayClaimsDidResetNotification =
    @"MWScreenSaverDisplayClaimsDidResetNotification";
NSNotificationName const MWScreenSaverDisplayClaimWasDisplacedNotification =
    @"MWScreenSaverDisplayClaimWasDisplacedNotification";

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
@property(nonatomic, strong) NSMapTable<id, NSNumber *> *animationStartOrders;
@property(nonatomic, strong) NSHashTable<id> *attachedOwners;
@property(nonatomic, strong) NSLock *lock;
@property(nonatomic) NSTimeInterval lastAnimationStartTime;
@property(nonatomic) NSUInteger animationSession;
@property(nonatomic) NSUInteger nextAnimationStartOrder;
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
        _animationStartOrders = [NSMapTable weakToStrongObjectsMapTable];
        _attachedOwners = [NSHashTable weakObjectsHashTable];
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
        [self.animationStartOrders removeAllObjects];
        [self.attachedOwners removeAllObjects];
        self.animationSession += 1;
        didReset = YES;
    }
    if (![self.animationStartOrders objectForKey:owner]) {
        self.nextAnimationStartOrder += 1;
        [self.animationStartOrders setObject:@(self.nextAnimationStartOrder)
                                     forKey:owner];
    }
    self.lastAnimationStartTime = startTime;
    session = self.animationSession;
    [self.lock unlock];

    os_log_with_type(MWScreenSaverDiagnosticLog(), OS_LOG_TYPE_DEFAULT,
        "animation-session session=%{public}lu action=%{public}s releasedClaims=%{public}lu",
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
            MWDiagnosticFingerprintForString(display.displayID),
            display.size.width,
            display.size.height]];
    }
    os_log_with_type(MWScreenSaverDiagnosticLog(), OS_LOG_TYPE_DEFAULT,
        "resolve view=%{public}.0fx%{public}.0f screenAttached=%{public}s preferred=%{public}@ candidates=%{public}@",
        viewSize.width,
        viewSize.height,
        preferredID.length > 0 ? "yes" : "no",
        preferredID.length > 0 ? MWDiagnosticFingerprintForString(preferredID) : @"none",
        [candidateSummaries componentsJoinedByString:@","]);

    NSString *resolvedID = nil;
    id displacedOwner = nil;
    [self.lock lock];
    @try {
        do {
            NSString *existingID = [self.assignments objectForKey:owner];
            if (preferredID.length > 0 &&
                [self displayWithID:preferredID inDisplays:displays]) {
                displacedOwner = [self ownerAssignedToDisplayID:preferredID excludingOwner:owner];
                if (displacedOwner) {
                    [self.assignments removeObjectForKey:displacedOwner];
                }
                [self.attachedOwners addObject:owner];
                [self.assignments setObject:preferredID forKey:owner];
                resolvedID = preferredID;
                os_log_with_type(MWScreenSaverDiagnosticLog(), OS_LOG_TYPE_DEFAULT,
                    "route display=%{public}@ reason=%{public}s displaced=%{public}s",
                    MWDiagnosticFingerprintForString(preferredID),
                    displacedOwner ? "attached-screen-takeover" : "attached-screen",
                    displacedOwner ? "yes" : "no");
                break;
            }

            MWScreenSaverDisplay *existing = [self displayWithID:existingID inDisplays:displays];
            if (existing && [self size:existing.size matchesSize:viewSize]) {
                resolvedID = existingID;
                os_log_with_type(MWScreenSaverDiagnosticLog(), OS_LOG_TYPE_DEFAULT,
                    "route display=%{public}@ reason=existing-claim",
                    MWDiagnosticFingerprintForString(existingID));
                break;
            }
            [self.assignments removeObjectForKey:owner];

            for (MWScreenSaverDisplay *display in displays) {
                if ([self size:display.size matchesSize:viewSize] &&
                    [self displayID:display.displayID isAvailableToOwner:owner]) {
                    [self.assignments setObject:display.displayID forKey:owner];
                    resolvedID = display.displayID;
                    os_log_with_type(MWScreenSaverDiagnosticLog(), OS_LOG_TYPE_DEFAULT,
                        "route display=%{public}@ reason=matching-dimensions",
                        MWDiagnosticFingerprintForString(display.displayID));
                    break;
                }
            }
            if (resolvedID) {
                break;
            }

            NSNumber *ownerOrder = [self.animationStartOrders objectForKey:owner];
            NSUInteger oldestOrder = NSUIntegerMax;
            MWScreenSaverDisplay *takeoverDisplay = nil;
            for (id existingOwner in self.assignments) {
                if (existingOwner == owner || [self.attachedOwners containsObject:existingOwner]) {
                    continue;
                }
                NSString *assignedID = [self.assignments objectForKey:existingOwner];
                MWScreenSaverDisplay *assignedDisplay = [self displayWithID:assignedID
                                                                  inDisplays:displays];
                NSNumber *existingOrder = [self.animationStartOrders objectForKey:existingOwner];
                // Retained views can reclaim on layout after a session reset without
                // starting again. Their missing order ranks before current-session owners.
                if (!assignedDisplay || !ownerOrder ||
                    existingOrder.unsignedIntegerValue >= ownerOrder.unsignedIntegerValue ||
                    ![self size:assignedDisplay.size matchesSize:viewSize] ||
                    existingOrder.unsignedIntegerValue >= oldestOrder) {
                    continue;
                }
                oldestOrder = existingOrder.unsignedIntegerValue;
                takeoverDisplay = assignedDisplay;
                displacedOwner = existingOwner;
            }
            if (takeoverDisplay && displacedOwner) {
                [self.assignments removeObjectForKey:displacedOwner];
                [self.assignments setObject:takeoverDisplay.displayID forKey:owner];
                resolvedID = takeoverDisplay.displayID;
                os_log_with_type(MWScreenSaverDiagnosticLog(), OS_LOG_TYPE_DEFAULT,
                    "route display=%{public}@ reason=matching-dimensions-takeover displaced=yes",
                    MWDiagnosticFingerprintForString(takeoverDisplay.displayID));
                break;
            }

            NSUInteger availableCount = 0;
            for (MWScreenSaverDisplay *display in displays) {
                if ([self displayID:display.displayID isAvailableToOwner:owner]) {
                    availableCount += 1;
                }
            }
            os_log_with_type(MWScreenSaverDiagnosticLog(), OS_LOG_TYPE_ERROR,
                "route display=none reason=ambiguous-or-no-match available=%{public}lu",
                (unsigned long)availableCount);
        } while (NO);
    } @finally {
        [self.lock unlock];
    }

    if (displacedOwner) {
        [NSNotificationCenter.defaultCenter
            postNotificationName:MWScreenSaverDisplayClaimWasDisplacedNotification
                          object:displacedOwner];
    }
    return resolvedID;
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
    [self.animationStartOrders removeObjectForKey:owner];
    [self.attachedOwners removeObject:owner];
    [self.lock unlock];
    os_log_with_type(MWScreenSaverDiagnosticLog(), OS_LOG_TYPE_DEFAULT,
        "release display=%{public}@",
        displayID.length > 0 ? MWDiagnosticFingerprintForString(displayID) : @"none");
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
