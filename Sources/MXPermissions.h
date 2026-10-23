#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const MXAccessibilityTrustDidChangeNotification;

/// Tracks Accessibility trust while the app runs, so granting it in System
/// Settings takes effect without a relaunch.
@interface MXPermissions : NSObject

@property (class, nonatomic, readonly) MXPermissions *shared;

@property (nonatomic, readonly, getter=isAccessibilityTrusted) BOOL accessibilityTrusted;
/// YES when this Mac granted access to Mixologist before but no longer does —
/// usually a rebuild with a different signature, which leaves a stale entry
/// that System Settings still shows as enabled.
@property (nonatomic, readonly) BOOL accessibilityWasLost;

- (void)startWatching;

/// Registers Mixologist in the Accessibility list and leads the user to it.
- (void)requestAccessibility;
- (void)openAccessibilitySettings;

/// Removes Mixologist's Accessibility entry (stale or not) and asks again.
- (void)resetAccessibilityWithCompletion:(nullable void (^)(BOOL success))completion;

/// Starts a fresh copy of the app once this process has exited, then quits.
+ (void)relaunch;
/// Same, but opens the app bundle at `bundlePath` instead of this one.
+ (void)relaunchAtPath:(NSString *)bundlePath;

@end

NS_ASSUME_NONNULL_END
