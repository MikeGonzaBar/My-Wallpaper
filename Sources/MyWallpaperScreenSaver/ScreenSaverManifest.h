#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MWScreenSaverManifest : NSObject

@property(nonatomic, readonly, getter=isMuted) BOOL muted;
@property(nonatomic, copy, readonly) NSString *scaling;

+ (nullable instancetype)loadFromApplicationSupport;
+ (nullable instancetype)loadFromApplicationSupportDirectory:(NSURL *)directory;
- (NSArray<NSURL *> *)videoURLsForDisplayID:(nullable NSString *)displayID preview:(BOOL)isPreview;

@end

NS_ASSUME_NONNULL_END
