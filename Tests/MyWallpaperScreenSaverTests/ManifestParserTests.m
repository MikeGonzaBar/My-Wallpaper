#import <Foundation/Foundation.h>

#import "ScreenSaverManifest.h"

@interface MWScreenSaverManifest (Testing)
+ (nullable NSURL *)applicationSupportDirectoryForHomeDirectory:(nullable NSString *)homeDirectory;
@end

static void Require(BOOL condition, NSString *message) {
    if (!condition) {
        NSLog(@"FAILED: %@", message);
        exit(1);
    }
}

static void WriteJSON(NSDictionary *value, NSURL *URL) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    Require([data writeToURL:URL atomically:YES], @"Could not write JSON fixture");
}

static NSURL *MakeDirectory(void) {
    NSURL *directory = [NSURL fileURLWithPath:[NSTemporaryDirectory()
        stringByAppendingPathComponent:NSUUID.UUID.UUIDString]
        isDirectory:YES];
    Require([[NSFileManager defaultManager] createDirectoryAtURL:directory
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:nil],
            @"Could not create fixture directory");
    return directory;
}

static NSURL *MakeVideo(NSURL *directory, NSString *name) {
    NSURL *URL = [directory URLByAppendingPathComponent:name];
    Require([[NSData data] writeToURL:URL atomically:YES], @"Could not create video fixture");
    return URL;
}

static void RemoveDirectory(NSURL *directory) {
    [[NSFileManager defaultManager] removeItemAtURL:directory error:nil];
}

static void TestVersionOneManifest(void) {
    NSURL *directory = MakeDirectory();
    NSURL *one = MakeVideo(directory, @"one.mp4");
    NSURL *two = MakeVideo(directory, @"two.mp4");
    NSDictionary *manifest = @{
        @"schemaVersion": @1,
        @"isMuted": @NO,
        @"scaling": @"fit",
        @"fallbackDisplayID": @"fallback",
        @"displays": @[
            @{@"displayID": @"fallback", @"orderedVideoPaths": @[one.path, two.path]},
            @{@"displayID": @"missing", @"orderedVideoPaths": @[@"/missing.mp4"]}
        ]
    };
    WriteJSON(manifest, [directory URLByAppendingPathComponent:@"screensaver-manifest-v1.json"]);

    MWScreenSaverManifest *parsed =
        [MWScreenSaverManifest loadFromApplicationSupportDirectory:directory];
    Require(parsed != nil, @"Valid v1 manifest should parse");
    Require(!parsed.isMuted, @"Mute should parse");
    Require([parsed.scaling isEqualToString:@"fit"], @"Scaling should parse");
    Require([[parsed videoURLsForDisplayID:@"fallback" preview:NO]
        isEqualToArray:@[one, two]], @"Ordered paths should be preserved");
    Require([[parsed videoURLsForDisplayID:@"unconfigured" preview:NO]
        isEqualToArray:@[one, two]], @"Unknown display should use fallback");
    Require([[parsed videoURLsForDisplayID:@"missing" preview:NO]
        isEqualToArray:@[one, two]], @"Unplayable display should use fallback");
    Require([[parsed videoURLsForDisplayID:@"missing" preview:YES]
        isEqualToArray:@[one, two]], @"System Settings preview should use fallback");
    RemoveDirectory(directory);
}

static void TestMissingFallbackUsesFirstPlayableDisplay(void) {
    NSURL *directory = MakeDirectory();
    NSURL *one = MakeVideo(directory, @"one.mp4");
    NSDictionary *manifest = @{
        @"schemaVersion": @1,
        @"isMuted": @YES,
        @"scaling": @"fill",
        @"fallbackDisplayID": @"not-present",
        @"displays": @[
            @{@"displayID": @"first", @"orderedVideoPaths": @[one.path]}
        ]
    };
    WriteJSON(manifest, [directory URLByAppendingPathComponent:@"screensaver-manifest-v1.json"]);

    MWScreenSaverManifest *parsed =
        [MWScreenSaverManifest loadFromApplicationSupportDirectory:directory];
    Require([[parsed videoURLsForDisplayID:@"unknown" preview:NO]
        isEqualToArray:@[one]], @"Invalid fallback ID should use first playable display");
    RemoveDirectory(directory);
}

static void TestInvalidManifestTypesFailClosed(void) {
    NSURL *directory = MakeDirectory();
    NSDictionary *manifest = @{
        @"schemaVersion": @1,
        @"isMuted": @"yes",
        @"scaling": @"fill",
        @"fallbackDisplayID": @"display",
        @"displays": @[]
    };
    WriteJSON(manifest, [directory URLByAppendingPathComponent:@"screensaver-manifest-v1.json"]);
    Require([MWScreenSaverManifest loadFromApplicationSupportDirectory:directory] == nil,
            @"Invalid manifest field types should fail closed");

    NSURL *numericMuteDirectory = MakeDirectory();
    NSDictionary *numericMute = @{
        @"schemaVersion": @1,
        @"isMuted": @1,
        @"scaling": @"fill",
        @"fallbackDisplayID": @"display",
        @"displays": @[]
    };
    WriteJSON(numericMute,
              [numericMuteDirectory URLByAppendingPathComponent:@"screensaver-manifest-v1.json"]);
    Require([MWScreenSaverManifest loadFromApplicationSupportDirectory:numericMuteDirectory] == nil,
            @"Numeric mute values should not be accepted as booleans");

    NSURL *booleanSchemaDirectory = MakeDirectory();
    NSDictionary *booleanSchema = @{
        @"schemaVersion": @YES,
        @"isMuted": @YES,
        @"scaling": @"fill",
        @"fallbackDisplayID": @"display",
        @"displays": @[]
    };
    WriteJSON(booleanSchema,
              [booleanSchemaDirectory URLByAppendingPathComponent:@"screensaver-manifest-v1.json"]);
    Require([MWScreenSaverManifest loadFromApplicationSupportDirectory:booleanSchemaDirectory] == nil,
            @"Boolean schema values should not be accepted as version numbers");
    RemoveDirectory(directory);
    RemoveDirectory(numericMuteDirectory);
    RemoveDirectory(booleanSchemaDirectory);
}

static void TestInvalidVersionDoesNotUseLegacyFallback(void) {
    NSURL *directory = MakeDirectory();
    WriteJSON(@{@"schemaVersion": @2},
              [directory URLByAppendingPathComponent:@"screensaver-manifest-v1.json"]);
    WriteJSON(@{@"screens": @[], @"videos": @[]},
              [directory URLByAppendingPathComponent:@"settings.json"]);
    Require([MWScreenSaverManifest loadFromApplicationSupportDirectory:directory] == nil,
            @"Unknown schema should fail closed");
    RemoveDirectory(directory);
}

static void TestMalformedManifestFailsClosed(void) {
    NSURL *directory = MakeDirectory();
    NSURL *URL = [directory URLByAppendingPathComponent:@"screensaver-manifest-v1.json"];
    Require([[@"not-json" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:URL atomically:YES],
            @"Could not write malformed fixture");
    Require([MWScreenSaverManifest loadFromApplicationSupportDirectory:directory] == nil,
            @"Malformed manifest should fail closed");
    RemoveDirectory(directory);
}

static void TestLegacyFallback(void) {
    NSURL *directory = MakeDirectory();
    NSURL *one = MakeVideo(directory, @"one.mp4");
    NSDictionary *legacy = @{
        @"isMuted": @YES,
        @"scaling": @"Fill screen",
        @"videos": @[@{@"id": @"one", @"path": one.path}],
        @"screens": @[@{
            @"screenID": @"display",
            @"mode": @"Single video",
            @"videoIDs": @[@"one"],
            @"startVideoID": @"one"
        }]
    };
    WriteJSON(legacy, [directory URLByAppendingPathComponent:@"settings.json"]);

    MWScreenSaverManifest *parsed =
        [MWScreenSaverManifest loadFromApplicationSupportDirectory:directory];
    Require(parsed != nil, @"Legacy settings should parse when v1 is absent");
    Require(parsed.isMuted, @"Legacy mute should parse");
    Require([[parsed videoURLsForDisplayID:@"display" preview:NO]
        isEqualToArray:@[one]], @"Legacy video should resolve");
    RemoveDirectory(directory);
}

static void TestApplicationSupportPathUsesAccountHome(void) {
    NSURL *directory = [MWScreenSaverManifest
        applicationSupportDirectoryForHomeDirectory:@"/Users/example"];
    Require([directory.path
        isEqualToString:@"/Users/example/Library/Application Support/My Wallpaper"],
        @"Native host path should resolve from the account home directory");
    Require([MWScreenSaverManifest applicationSupportDirectoryForHomeDirectory:nil] == nil,
            @"Missing account home should fail closed");
}

int main(void) {
    @autoreleasepool {
        TestVersionOneManifest();
        TestMissingFallbackUsesFirstPlayableDisplay();
        TestInvalidManifestTypesFailClosed();
        TestInvalidVersionDoesNotUseLegacyFallback();
        TestMalformedManifestFailsClosed();
        TestLegacyFallback();
        TestApplicationSupportPathUsesAccountHome();
        printf("Screen saver manifest parser tests passed.\n");
    }
    return 0;
}
