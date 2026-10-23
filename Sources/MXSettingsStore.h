#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MXSettingsStore : NSObject

@property (nonatomic, copy) NSSet<NSString *> *hiddenBundleIdentifiers;
@property (nonatomic) BOOL hasShownWelcome;
@property (nonatomic) BOOL revealForFifteenSeconds;

- (BOOL)isBundleHidden:(NSString *)bundleIdentifier;
- (void)setBundle:(NSString *)bundleIdentifier hidden:(BOOL)hidden;

@end

NS_ASSUME_NONNULL_END
