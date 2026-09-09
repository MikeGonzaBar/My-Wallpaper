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

NSString *MWDiagnosticFingerprintForString(NSString *value) {
    NSData *valueData = [value dataUsingEncoding:NSUTF8StringEncoding];
    if (valueData.length == 0 || valueData.length > UINT32_MAX) {
        return @"unavailable";
    }

    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(valueData.bytes, (CC_LONG)valueData.length, digest);

    NSMutableString *fingerprint = [NSMutableString stringWithCapacity:12];
    for (NSUInteger index = 0; index < 6; index += 1) {
        [fingerprint appendFormat:@"%02x", digest[index]];
    }
    return fingerprint;
}

NSString *MWVideoFingerprint(NSURL *URL) {
    return MWDiagnosticFingerprintForString(URL.path);
}
