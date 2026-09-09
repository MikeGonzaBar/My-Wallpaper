#import <Foundation/Foundation.h>
#import <os/log.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT os_log_t MWScreenSaverDiagnosticLog(void);
FOUNDATION_EXPORT NSString *MWDiagnosticFingerprintForString(NSString *value);
FOUNDATION_EXPORT NSString *MWVideoFingerprint(NSURL *URL);

NS_ASSUME_NONNULL_END
