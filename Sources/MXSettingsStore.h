#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MXSettingsStore : NSObject

@property (nonatomic, copy) NSSet<NSString *> *hiddenBundleIdentifiers;
/// `MBSystemItemIdentifier` raw values of Apple modules (Clock, Wi-Fi, …) the
/// user chose to hide.
@property (nonatomic, copy) NSSet<NSNumber *> *hiddenSystemItems;
@property (nonatomic) BOOL hasShownWelcome;
@property (nonatomic) BOOL revealForFifteenSeconds;

- (BOOL)isBundleHidden:(NSString *)bundleIdentifier;
- (void)setBundle:(NSString *)bundleIdentifier hidden:(BOOL)hidden;
- (BOOL)isSystemItemHidden:(NSInteger)rawValue;
- (void)setSystemItem:(NSInteger)rawValue hidden:(BOOL)hidden;

@end

NS_ASSUME_NONNULL_END
