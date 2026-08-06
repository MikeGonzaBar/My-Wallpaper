#import "ScreenSaverManifest.h"
#import "ScreenSaverDiagnostics.h"

#import <errno.h>
#import <pwd.h>
#import <string.h>
#import <unistd.h>

@interface MWScreenSaverManifest ()
@property(nonatomic, readwrite, getter=isMuted) BOOL muted;
@property(nonatomic, copy, readwrite) NSString *scaling;
@property(nonatomic, copy) NSString *fallbackDisplayID;
@property(nonatomic, copy) NSDictionary<NSString *, NSArray<NSURL *> *> *URLsByDisplayID;
+ (nullable NSURL *)applicationSupportDirectory;
+ (nullable NSURL *)applicationSupportDirectoryForHomeDirectory:(nullable NSString *)homeDirectory;
@end

@implementation MWScreenSaverManifest

+ (instancetype)loadFromApplicationSupport {
    NSURL *directory = [self applicationSupportDirectory];
    return directory ? [self loadFromApplicationSupportDirectory:directory] : nil;
}

+ (instancetype)loadFromApplicationSupportDirectory:(NSURL *)directory {
    NSURL *manifestURL = [directory URLByAppendingPathComponent:@"screensaver-manifest-v1.json"];
    NSData *manifestData = [NSData dataWithContentsOfURL:manifestURL];
    if (manifestData) {
        MWScreenSaverManifest *manifest =
            [self parseVersionOneManifest:[self dictionaryFromData:manifestData]];
        os_log_with_type(MWScreenSaverDiagnosticLog(),
                         manifest ? OS_LOG_TYPE_DEFAULT : OS_LOG_TYPE_ERROR,
                         "manifest source=v1 result=%{public}s",
                         manifest ? "loaded" : "invalid");
        return manifest;
    }

    NSURL *legacyURL = [directory URLByAppendingPathComponent:@"settings.json"];
    MWScreenSaverManifest *manifest = [self parseLegacySettings:[self dictionaryAtURL:legacyURL]];
    os_log_with_type(MWScreenSaverDiagnosticLog(),
                     manifest ? OS_LOG_TYPE_DEFAULT : OS_LOG_TYPE_ERROR,
                     "manifest source=legacy result=%{public}s",
                     manifest ? "loaded" : "missing-or-invalid");
    return manifest;
}

- (NSArray<NSURL *> *)videoURLsForDisplayID:(NSString *)displayID preview:(BOOL)isPreview {
    if (!isPreview && displayID.length > 0) {
        NSArray<NSURL *> *matched = self.URLsByDisplayID[displayID];
        if (matched.count > 0) {
            return matched;
        }
    }
    NSArray<NSURL *> *fallback = self.URLsByDisplayID[self.fallbackDisplayID];
    return fallback.count > 0 ? fallback : @[];
}

+ (MWScreenSaverManifest *)parseVersionOneManifest:(NSDictionary *)dictionary {
    NSNumber *schemaVersion = dictionary[@"schemaVersion"];
    NSNumber *isMuted = dictionary[@"isMuted"];
    if (![dictionary isKindOfClass:NSDictionary.class] ||
        ![schemaVersion isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)schemaVersion) == CFBooleanGetTypeID() ||
        schemaVersion.integerValue != 1 ||
        ![isMuted isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)isMuted) != CFBooleanGetTypeID() ||
        ![dictionary[@"scaling"] isKindOfClass:NSString.class] ||
        ![dictionary[@"fallbackDisplayID"] isKindOfClass:NSString.class] ||
        ![dictionary[@"displays"] isKindOfClass:NSArray.class]) {
        return nil;
    }

    NSString *scaling = dictionary[@"scaling"];
    if (![scaling isEqualToString:@"fill"] && ![scaling isEqualToString:@"fit"]) {
        return nil;
    }

    NSMutableDictionary<NSString *, NSArray<NSURL *> *> *URLsByDisplayID =
        [NSMutableDictionary dictionary];
    NSString *firstPlayableDisplayID = nil;
    for (id value in dictionary[@"displays"]) {
        if (![value isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSDictionary *display = value;
        NSString *displayID = display[@"displayID"];
        NSArray *paths = display[@"orderedVideoPaths"];
        if (![displayID isKindOfClass:NSString.class] || displayID.length == 0 ||
            ![paths isKindOfClass:NSArray.class]) {
            continue;
        }
        NSArray<NSURL *> *URLs = [self playableURLsFromPaths:paths];
        if (URLs.count > 0) {
            URLsByDisplayID[displayID] = URLs;
            if (!firstPlayableDisplayID) {
                firstPlayableDisplayID = displayID;
            }
        }
    }
    if (URLsByDisplayID.count == 0) {
        return nil;
    }

    NSString *fallbackDisplayID = dictionary[@"fallbackDisplayID"];
    if (URLsByDisplayID[fallbackDisplayID].count == 0) {
        fallbackDisplayID = firstPlayableDisplayID;
    }

    MWScreenSaverManifest *result = [[self alloc] init];
    result.muted = isMuted.boolValue;
    result.scaling = scaling;
    result.fallbackDisplayID = fallbackDisplayID;
    result.URLsByDisplayID = URLsByDisplayID;
    [result logDiagnosticsWithSource:@"v1"];
    return result;
}

+ (MWScreenSaverManifest *)parseLegacySettings:(NSDictionary *)settings {
    if (![settings isKindOfClass:NSDictionary.class] ||
        ![settings[@"screens"] isKindOfClass:NSArray.class] ||
        ![settings[@"videos"] isKindOfClass:NSArray.class]) {
        return nil;
    }

    NSMutableDictionary<NSString *, NSString *> *pathsByID = [NSMutableDictionary dictionary];
    for (id value in settings[@"videos"]) {
        if (![value isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSDictionary *video = value;
        NSString *videoID = video[@"id"];
        NSString *path = video[@"path"];
        if ([videoID isKindOfClass:NSString.class] && videoID.length > 0 &&
            [path isKindOfClass:NSString.class] && path.length > 0) {
            pathsByID[videoID] = path;
        }
    }

    NSMutableDictionary<NSString *, NSArray<NSURL *> *> *URLsByDisplayID =
        [NSMutableDictionary dictionary];
    NSString *firstPlayableDisplayID = nil;
    for (id value in settings[@"screens"]) {
        if (![value isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSDictionary *screen = value;
        NSString *displayID = screen[@"screenID"];
        NSArray *videoIDs = screen[@"videoIDs"];
        if (![displayID isKindOfClass:NSString.class] || displayID.length == 0 ||
            ![videoIDs isKindOfClass:NSArray.class]) {
            continue;
        }

        NSMutableArray<NSString *> *playableIDs = [NSMutableArray array];
        NSMutableArray<NSString *> *paths = [NSMutableArray array];
        for (id videoID in videoIDs) {
            if (![videoID isKindOfClass:NSString.class]) {
                continue;
            }
            NSString *path = pathsByID[videoID];
            if (path.length > 0 && [[NSFileManager defaultManager] isReadableFileAtPath:path]) {
                [playableIDs addObject:videoID];
                [paths addObject:path];
            }
        }
        NSArray<NSURL *> *URLs = [self playableURLsFromPaths:paths];
        if (URLs.count == 0) {
            continue;
        }

        NSString *startVideoID = screen[@"startVideoID"];
        NSUInteger startIndex = [playableIDs indexOfObject:startVideoID];
        if (startIndex == NSNotFound || startIndex >= URLs.count) {
            startIndex = 0;
        }
        if ([screen[@"mode"] isEqualToString:@"Single video"]) {
            URLs = @[URLs[startIndex]];
        } else if (startIndex > 0) {
            URLs = [[URLs subarrayWithRange:NSMakeRange(startIndex, URLs.count - startIndex)]
                arrayByAddingObjectsFromArray:[URLs subarrayWithRange:NSMakeRange(0, startIndex)]];
        }
        URLsByDisplayID[displayID] = URLs;
        if (!firstPlayableDisplayID) {
            firstPlayableDisplayID = displayID;
        }
    }
    if (URLsByDisplayID.count == 0) {
        return nil;
    }

    MWScreenSaverManifest *result = [[self alloc] init];
    result.muted = [settings[@"isMuted"] boolValue];
    result.scaling = [settings[@"scaling"] isEqualToString:@"Fit to screen"] ? @"fit" : @"fill";
    result.fallbackDisplayID = firstPlayableDisplayID;
    result.URLsByDisplayID = URLsByDisplayID;
    [result logDiagnosticsWithSource:@"legacy"];
    return result;
}

- (void)logDiagnosticsWithSource:(NSString *)source {
    os_log_with_type(MWScreenSaverDiagnosticLog(), OS_LOG_TYPE_DEFAULT,
        "manifest-plan source=%{public}@ routes=%{public}lu fallback=%{public}@ muted=%{public}s scaling=%{public}@",
        source,
        (unsigned long)self.URLsByDisplayID.count,
        self.fallbackDisplayID,
        self.isMuted ? "yes" : "no",
        self.scaling);

    for (NSString *displayID in [self.URLsByDisplayID.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        NSArray<NSURL *> *URLs = self.URLsByDisplayID[displayID];
        NSMutableArray<NSString *> *fingerprints = [NSMutableArray arrayWithCapacity:URLs.count];
        for (NSURL *URL in URLs) {
            [fingerprints addObject:MWVideoFingerprint(URL)];
        }
        os_log_with_type(MWScreenSaverDiagnosticLog(), OS_LOG_TYPE_DEFAULT,
            "manifest-route display=%{public}@ videos=%{public}lu order=%{public}@",
            displayID,
            (unsigned long)URLs.count,
            [fingerprints componentsJoinedByString:@","]);
    }
}

+ (NSArray<NSURL *> *)playableURLsFromPaths:(NSArray *)paths {
    NSMutableArray<NSURL *> *URLs = [NSMutableArray array];
    for (id value in paths) {
        if (![value isKindOfClass:NSString.class]) {
            continue;
        }
        NSString *path = value;
        if (path.length > 0 && [[NSFileManager defaultManager] isReadableFileAtPath:path]) {
            [URLs addObject:[NSURL fileURLWithPath:path]];
        }
    }
    return URLs;
}

+ (NSDictionary *)dictionaryAtURL:(NSURL *)URL {
    NSData *data = [NSData dataWithContentsOfURL:URL];
    if (!data) {
        return nil;
    }
    return [self dictionaryFromData:data];
}

+ (NSDictionary *)dictionaryFromData:(NSData *)data {
    id JSON = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [JSON isKindOfClass:NSDictionary.class] ? JSON : nil;
}

+ (NSURL *)applicationSupportDirectory {
    // ScreenSaverEngine hosts legacy modules in a sandboxed extension. Foundation's
    // user-domain lookup is therefore redirected into the host's container instead
    // of the user's actual Library directory. Resolve the account home from the
    // password database so the native module reads the manifest written by the app.
    long suggestedBufferSize = sysconf(_SC_GETPW_R_SIZE_MAX);
    NSUInteger bufferSize = suggestedBufferSize > 0
        ? (NSUInteger)suggestedBufferSize
        : (NSUInteger)(16 * 1024);
    bufferSize = MAX(bufferSize, (NSUInteger)(16 * 1024));

    while (bufferSize <= 1024 * 1024) {
        NSMutableData *buffer = [NSMutableData dataWithLength:bufferSize];
        struct passwd passwordEntry;
        struct passwd *result = NULL;
        int status = getpwuid_r(getuid(),
                                &passwordEntry,
                                buffer.mutableBytes,
                                buffer.length,
                                &result);
        if (status == 0 && result && result->pw_dir && result->pw_dir[0] != '\0') {
            NSString *homeDirectory = [[NSFileManager defaultManager]
                stringWithFileSystemRepresentation:result->pw_dir
                                             length:strlen(result->pw_dir)];
            return [self applicationSupportDirectoryForHomeDirectory:homeDirectory];
        }
        if (status != ERANGE) {
            break;
        }
        bufferSize *= 2;
    }
    return nil;
}

+ (NSURL *)applicationSupportDirectoryForHomeDirectory:(NSString *)homeDirectory {
    if (homeDirectory.length == 0) {
        return nil;
    }
    return [[NSURL fileURLWithPath:homeDirectory isDirectory:YES]
        URLByAppendingPathComponent:@"Library/Application Support/My Wallpaper"
                         isDirectory:YES];
}

@end
