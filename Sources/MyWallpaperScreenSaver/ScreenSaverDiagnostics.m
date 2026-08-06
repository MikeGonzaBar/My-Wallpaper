#import "ScreenSaverDiagnostics.h"

#import <CommonCrypto/CommonDigest.h>

os_log_t MWScreenSaverDiagnosticLog(void) {
    static os_log_t log;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        log = os_log_create("com.prototype.mywallpaper.saver", "diagnostics");
    });
    return log;
}

NSString *MWVideoFingerprint(NSURL *URL) {
    NSData *pathData = [URL.path dataUsingEncoding:NSUTF8StringEncoding];
    if (pathData.length == 0 || pathData.length > UINT32_MAX) {
        return @"unavailable";
    }

    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(pathData.bytes, (CC_LONG)pathData.length, digest);

    NSMutableString *fingerprint = [NSMutableString stringWithCapacity:12];
    for (NSUInteger index = 0; index < 6; index += 1) {
        [fingerprint appendFormat:@"%02x", digest[index]];
    }
    return fingerprint;
}
