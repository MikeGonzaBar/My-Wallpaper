#import <Foundation/Foundation.h>

#import "ScreenSaverDiagnostics.h"

static void Require(BOOL condition, NSString *message) {
    if (!condition) {
        NSLog(@"FAILED: %@", message);
        exit(1);
    }
}

int main(void) {
    @autoreleasepool {
        NSURL *firstURL = [NSURL fileURLWithPath:@"/private/videos/first-secret-name.mp4"];
        NSURL *sameURL = [NSURL fileURLWithPath:@"/private/videos/first-secret-name.mp4"];
        NSURL *differentURL = [NSURL fileURLWithPath:@"/private/videos/second-secret-name.mp4"];

        NSString *first = MWVideoFingerprint(firstURL);
        Require(first.length == 12, @"Video fingerprints should be short and log-friendly");
        Require([first isEqualToString:MWVideoFingerprint(sameURL)],
                @"The same video path should produce a stable fingerprint");
        Require(![first isEqualToString:MWVideoFingerprint(differentURL)],
                @"Different video paths should produce different fingerprints");
        Require([first rangeOfString:@"secret"].location == NSNotFound,
                @"Fingerprints must not expose filenames or paths");

        printf("Screen saver diagnostics tests passed.\n");
    }
    return 0;
}
