#import <Foundation/Foundation.h>
#import "MXMenuBarScanner.h"
#import "MXSettingsStore.h"
#import "MXVisibilityPlan.h"

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const MXVisibilityDidChangeNotification;
extern NSNotificationName const MXScanDidChangeNotification;

@interface MXVisibilityController : NSObject

@property (nonatomic, strong, readonly) MXSettingsStore *store;
@property (nonatomic, strong, readonly) MXScanResult *lastScan;
@property (nonatomic, readonly, getter=isHidingActive) BOOL hidingActive;
@property (nonatomic, readonly, getter=isRevealing) BOOL revealing;
@property (nonatomic, readonly, getter=isPrivateAPIAvailable) BOOL privateAPIAvailable;
@property (nonatomic, readonly, copy) NSString *statusDescription;
@property (nonatomic, strong, readonly, nullable) NSError *lastError;

- (void)start;
- (void)stop;

- (void)refreshScanWithCompletion:(nullable void (^)(MXScanResult *result))completion;
- (void)refreshSoon;

- (void)setBundle:(NSString *)bundleIdentifier hidden:(BOOL)hidden;
- (BOOL)isBundleHidden:(NSString *)bundleIdentifier;
- (void)setSystemItem:(NSInteger)rawValue hidden:(BOOL)hidden;
- (BOOL)isSystemItemHidden:(NSInteger)rawValue;
/// Hidden apps plus hidden Apple modules.
@property (nonatomic, readonly) NSUInteger hiddenCount;
- (void)setRevealing:(BOOL)revealing;
- (void)revealForSeconds:(NSTimeInterval)seconds;
- (void)hideAllThirdPartyApps;
- (void)showAllAppsPermanently;
- (void)reapply;

@end

NS_ASSUME_NONNULL_END
