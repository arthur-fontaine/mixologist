#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Posted on the main queue after settings.json was edited outside Mixologist.
extern NSNotificationName const MXSettingsDidChangeNotification;

typedef NSString *MXHidingMethod NS_TYPED_ENUM;
/// macOS's menu bar visibility restriction: instant and released if Mixologist
/// dies, but it also hides Control Center modules such as Now Playing.
extern MXHidingMethod const MXHidingMethodRestriction;
/// Turns off each hidden app's "Allow in the Menu Bar" approval instead.
extern MXHidingMethod const MXHidingMethodPermission;

/// User configuration, mirrored to `~/.config/mixologist/settings.json`: edits
/// made in Settings are written there, and edits made to the file are applied
/// live. Internal state (welcome shown, permission journal) stays in defaults.
@interface MXSettingsStore : NSObject

@property (class, nonatomic, readonly) NSURL *defaultFileURL;

/// The store for `defaultFileURL`, migrating older NSUserDefaults settings into
/// the file the first time.
- (instancetype)init;
- (instancetype)initWithFileURL:(NSURL *)fileURL NS_DESIGNATED_INITIALIZER;

@property (nonatomic, readonly) NSURL *fileURL;

@property (nonatomic, copy) NSSet<NSString *> *hiddenBundleIdentifiers;
/// `MBSystemItemIdentifier` raw values of Apple modules (Clock, Wi-Fi, …) the
/// user chose to hide.
@property (nonatomic, copy) NSSet<NSNumber *> *hiddenSystemItems;
@property (nonatomic, copy) MXHidingMethod hidingMethod;

/// Problems found the last time the file was read, worded for its author.
@property (nonatomic, readonly, copy) NSArray<NSString *> *fileIssues;
/// NO while the file is not a JSON object. Nothing is written then, so a
/// half-finished edit is never overwritten.
@property (nonatomic, readonly) BOOL fileIsUsable;

@property (nonatomic) BOOL hasShownWelcome;

- (BOOL)isBundleHidden:(NSString *)bundleIdentifier;
- (void)setBundle:(NSString *)bundleIdentifier hidden:(BOOL)hidden;
- (BOOL)isSystemItemHidden:(NSInteger)rawValue;
- (void)setSystemItem:(NSInteger)rawValue hidden:(BOOL)hidden;

/// Follows edits to the file from now on.
- (void)startWatching;

/// Applies file contents as if they had just been read from disk, returning the
/// issues. Exposed for the self-test.
- (NSArray<NSString *> *)applyFileData:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
