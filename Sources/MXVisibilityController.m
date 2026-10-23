#import "MXVisibilityController.h"
#import "MXMenuBarPermissions.h"
#import "MXPermissions.h"
#import "MXPrivateAPI.h"

NSNotificationName const MXVisibilityDidChangeNotification = @"MXVisibilityDidChangeNotification";
NSNotificationName const MXScanDidChangeNotification = @"MXScanDidChangeNotification";

@interface MXVisibilityController ()
@property (nonatomic, strong, readwrite) MXSettingsStore *store;
@property (nonatomic, strong, readwrite) MXScanResult *lastScan;
@property (nonatomic) BOOL restrictionActive;
@property (nonatomic) BOOL permissionActive;
@property (nonatomic, readwrite, getter=isRevealing) BOOL revealing;
@property (nonatomic, readwrite, getter=isPrivateAPIAvailable) BOOL privateAPIAvailable;
@property (nonatomic, strong, nullable) NSError *restrictionError;
@property (nonatomic, strong, nullable) NSError *permissionError;
/// nil in the self-test, which must never touch the user's menu bar permissions.
@property (nonatomic, strong, nullable) MXMenuBarPermissions *permissions;
@property (nonatomic, copy) NSString *lastAppliedSignature;
@property (nonatomic) NSUInteger applyGeneration;
@property (nonatomic, strong, nullable) NSTimer *revealTimer;
@property (nonatomic, strong, nullable) NSTimer *periodicScanTimer;
@property (nonatomic, strong, nullable) NSTimer *debounceTimer;
@property (nonatomic, strong) dispatch_queue_t scanQueue;
@property (nonatomic) BOOL scanning;
@property (nonatomic) BOOL rescanRequested;
@property (nonatomic) BOOL reapplyRequested;
@property (nonatomic, strong) NSMutableArray<void (^)(MXScanResult *)> *queuedScanCompletions;
@end

@implementation MXVisibilityController

- (instancetype)init {
    return [self initWithStore:[[MXSettingsStore alloc] init] permissions:MXMenuBarPermissions.shared];
}

- (instancetype)initWithStore:(MXSettingsStore *)store permissions:(MXMenuBarPermissions *)permissions {
    self = [super init];
    if (self) {
        _store = store;
        _permissions = permissions;
        _lastScan = [[MXScanResult alloc] init];
        _scanQueue = dispatch_queue_create("dev.mixologist.scan", DISPATCH_QUEUE_SERIAL);
        _queuedScanCompletions = [NSMutableArray array];
        _privateAPIAvailable = MXAssessmentMode.shared.isAvailable;
    }
    return self;
}

- (void)start {
    [self registerWorkspaceObservers];
    [self.store startWatching];
    [self refreshScanWithCompletion:nil];

    __weak typeof(self) weakSelf = self;
    self.periodicScanTimer = [NSTimer scheduledTimerWithTimeInterval:20.0
                                                             repeats:YES
                                                               block:^(NSTimer *timer) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            return;
        }
        if (self.isHidingActive || self.revealing || self.hiddenCount > 0) {
            [self refreshScanWithCompletion:nil];
        }
    }];
}

- (void)stop {
    [self.revealTimer invalidate];
    [self.periodicScanTimer invalidate];
    [self.debounceTimer invalidate];
    self.revealTimer = nil;
    self.periodicScanTimer = nil;
    self.debounceTimer = nil;
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [MXAssessmentMode.shared invalidate];
    self.restrictionActive = NO;
    // Unlike the restriction, permissions outlive the process.
    [self applyPermissionHiding:[NSSet set]];
}

- (void)dealloc {
    [self stop];
}

- (void)registerWorkspaceObservers {
    NSNotificationCenter *workspaceCenter = NSWorkspace.sharedWorkspace.notificationCenter;
    for (NSNotificationName name in @[
             NSWorkspaceDidLaunchApplicationNotification,
             NSWorkspaceDidTerminateApplicationNotification,
             NSWorkspaceDidHideApplicationNotification,
             NSWorkspaceDidUnhideApplicationNotification,
             NSWorkspaceScreensDidSleepNotification,
             NSWorkspaceScreensDidWakeNotification,
             NSWorkspaceDidWakeNotification,
         ]) {
        [workspaceCenter addObserver:self
                           selector:@selector(workspaceDidChange:)
                               name:name
                             object:nil];
    }
    [NSNotificationCenter.defaultCenter addObserver:self
                                          selector:@selector(applicationDidBecomeActive:)
                                              name:NSApplicationDidBecomeActiveNotification
                                            object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                          selector:@selector(accessibilityTrustDidChange:)
                                              name:MXAccessibilityTrustDidChangeNotification
                                            object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                          selector:@selector(settingsFileDidChange:)
                                              name:MXSettingsDidChangeNotification
                                            object:self.store];
}

- (void)settingsFileDidChange:(NSNotification *)notification {
    [self applyVisibilityIfNeededForce:YES];
}

- (void)accessibilityTrustDidChange:(NSNotification *)notification {
    [self refreshScanWithCompletion:nil];
}

- (void)workspaceDidChange:(NSNotification *)notification {
    NSRunningApplication *app = notification.userInfo[NSWorkspaceApplicationKey];
    // The restriction lives in MenuBarAgent. When it restarts, our assertion is
    // gone even though nothing about the plan changed, so the signature check
    // alone would never re-install it.
    if ([notification.name isEqualToString:NSWorkspaceDidLaunchApplicationNotification] &&
        [app.bundleIdentifier isEqualToString:@"com.apple.MenuBarAgent"]) {
        self.reapplyRequested = YES;
    }
    [self refreshSoon];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    if (!self.privateAPIAvailable) {
        self.privateAPIAvailable = MXAssessmentMode.shared.isAvailable;
    }
    [self refreshSoon];
}

- (void)refreshSoon {
    [self.debounceTimer invalidate];
    __weak typeof(self) weakSelf = self;
    self.debounceTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                        repeats:NO
                                                          block:^(NSTimer *timer) {
        __strong typeof(weakSelf) self = weakSelf;
        [self refreshScanWithCompletion:nil];
    }];
}

- (void)refreshScanWithCompletion:(void (^)(MXScanResult *))completion {
    if (completion) {
        [self.queuedScanCompletions addObject:[completion copy]];
    }
    if (self.scanning) {
        // A scan already in flight may predate whatever prompted this request
        // (an Accessibility grant, a launched app), so queue a fresh one.
        self.rescanRequested = YES;
        return;
    }
    [self startScan];
}

- (void)startScan {
    self.scanning = YES;
    self.rescanRequested = NO;
    NSArray<void (^)(MXScanResult *)> *completions = [self.queuedScanCompletions copy];
    [self.queuedScanCompletions removeAllObjects];

    __weak typeof(self) weakSelf = self;
    dispatch_async(self.scanQueue, ^{
        MXScanResult *result = [[MXMenuBarScanner alloc] scan];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) {
                return;
            }
            self.scanning = NO;
            self.lastScan = result;
            BOOL force = self.reapplyRequested;
            self.reapplyRequested = NO;
            [self applyVisibilityIfNeededForce:force];
            [NSNotificationCenter.defaultCenter postNotificationName:MXScanDidChangeNotification
                                                              object:self];
            for (void (^completion)(MXScanResult *) in completions) {
                completion(result);
            }
            if (self.rescanRequested) {
                [self startScan];
            }
        });
    });
}

- (void)setBundle:(NSString *)bundleIdentifier hidden:(BOOL)hidden {
    [self.store setBundle:bundleIdentifier hidden:hidden];
    [self applyVisibilityIfNeededForce:YES];
}

- (BOOL)isBundleHidden:(NSString *)bundleIdentifier {
    return [self.store isBundleHidden:bundleIdentifier];
}

- (void)setSystemItem:(NSInteger)rawValue hidden:(BOOL)hidden {
    [self.store setSystemItem:rawValue hidden:hidden];
    [self applyVisibilityIfNeededForce:YES];
}

- (BOOL)isSystemItemHidden:(NSInteger)rawValue {
    return [self.store isSystemItemHidden:rawValue];
}

- (BOOL)isHidingActive {
    return self.restrictionActive || self.permissionActive;
}

- (NSError *)lastError {
    return self.restrictionError ?: self.permissionError;
}

/// Makes exactly `bundleIdentifiers` hidden through their menu bar permission.
/// An empty set turns back on everything Mixologist turned off, which is how
/// revealing, Show All, switching method and quitting restore apps.
- (void)applyPermissionHiding:(NSSet<NSString *> *)bundleIdentifiers {
    if (!self.permissions) {
        return;
    }
    NSError *error = nil;
    if ([self.permissions turnOffExactly:bundleIdentifiers error:&error]) {
        self.permissionError = nil;
        self.permissionActive = bundleIdentifiers.count > 0;
    } else {
        self.permissionError = error;
        self.permissionActive = NO;
    }
}

- (NSUInteger)hiddenCount {
    return self.store.hiddenBundleIdentifiers.count + self.store.hiddenSystemItems.count;
}

- (void)setRevealing:(BOOL)revealing {
    if (revealing == _revealing) {
        return;
    }
    // Assign the ivar directly: `self.revealing = ...` would re-enter this
    // custom setter recursively and overflow the stack.
    _revealing = revealing;
    [self.revealTimer invalidate];
    self.revealTimer = nil;
    if (revealing) {
        [MXAssessmentMode.shared invalidate];
        self.restrictionActive = NO;
        [self applyPermissionHiding:[NSSet set]];
        self.lastAppliedSignature = @"";
        [self notifyVisibilityChanged];
    } else {
        [self applyVisibilityIfNeededForce:YES];
    }
}

- (void)revealForSeconds:(NSTimeInterval)seconds {
    [self setRevealing:YES];
    [self.revealTimer invalidate];
    __weak typeof(self) weakSelf = self;
    self.revealTimer = [NSTimer scheduledTimerWithTimeInterval:MAX(1.0, seconds)
                                                       repeats:NO
                                                         block:^(NSTimer *timer) {
        __strong typeof(weakSelf) self = weakSelf;
        [self setRevealing:NO];
    }];
}

- (void)hideAllThirdPartyApps {
    NSMutableSet *hidden = [self.store.hiddenBundleIdentifiers mutableCopy];
    for (NSString *bundleIdentifier in self.lastScan.thirdPartyBundleIdentifiers) {
        [hidden addObject:bundleIdentifier];
    }
    self.store.hiddenBundleIdentifiers = hidden;
    [self applyVisibilityIfNeededForce:YES];
}

- (void)showAllAppsPermanently {
    self.store.hiddenBundleIdentifiers = [NSSet set];
    self.store.hiddenSystemItems = [NSSet set];
    [self.revealTimer invalidate];
    self.revealTimer = nil;
    self.revealing = NO;
    [self applyVisibilityIfNeededForce:YES];
}

- (void)reapply {
    [self applyVisibilityIfNeededForce:YES];
}

- (void)applyVisibilityIfNeededForce:(BOOL)force {
    self.privateAPIAvailable = MXAssessmentMode.shared.isAvailable;

    NSSet<NSString *> *hidden = self.store.hiddenBundleIdentifiers;
    NSSet<NSString *> *byPermission = [NSSet set];
    if ([self.store.hidingMethod isEqualToString:MXHidingMethodPermission] && self.permissions.isAvailable) {
        byPermission = [MXVisibilityPlan bundlesHiddenByPermissionAmong:hidden
                                                    ownBundleIdentifier:NSBundle.mainBundle.bundleIdentifier];
    }
    // Both sides run every time, so revealing, Show All and switching method
    // undo whichever one is no longer wanted.
    [self applyPermissionHiding:self.revealing ? [NSSet set] : byPermission];
    NSMutableSet<NSString *> *byRestriction = [hidden mutableCopy];
    [byRestriction minusSet:byPermission];
    hidden = byRestriction;

    MXVisibilityPlan *plan = [MXVisibilityPlan planWithScannedBundleIdentifiers:
                                  [NSSet setWithArray:self.lastScan.thirdPartyBundleIdentifiers]
                                             runningBundleIdentifiers:
                                  [NSSet setWithArray:self.lastScan.runningBundleIdentifiers]
                                                   hiddenBundleIdentifiers:hidden
                                                         hiddenSystemItems:self.store.hiddenSystemItems
                                                  ownBundleIdentifier:NSBundle.mainBundle.bundleIdentifier];

    if (!plan.shouldRestrict || self.revealing) {
        [MXAssessmentMode.shared invalidate];
        self.restrictionActive = NO;
        self.lastAppliedSignature = @"";
        if (!plan.shouldRestrict) {
            self.restrictionError = nil;
        }
        [self notifyVisibilityChanged];
        return;
    }

    if (!self.privateAPIAvailable) {
        self.restrictionError = [NSError errorWithDomain:@"dev.mixologist.assessment"
                                            code:10
                                        userInfo:@{NSLocalizedDescriptionKey:
                                                       MXAssessmentMode.shared.unavailableReason ?:
                                                           @"The menu bar visibility API is unavailable on this Mac."}];
        self.restrictionActive = NO;
        [self notifyVisibilityChanged];
        return;
    }

    if (!force && self.restrictionActive && [plan.signature isEqualToString:self.lastAppliedSignature]) {
        return;
    }

    self.lastAppliedSignature = plan.signature;
    NSUInteger generation = ++self.applyGeneration;
    __weak typeof(self) weakSelf = self;
    BOOL started = [MXAssessmentMode.shared activateWithAllowedSystemItems:plan.allowedSystemItemRawValues
                                                   allowedBundleIdentifiers:plan.allowedBundleIdentifiers
                                                                completion:^(NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || generation != self.applyGeneration) {
            return;
        }
        if (error) {
            self.restrictionActive = NO;
            self.restrictionError = error;
            self.lastAppliedSignature = @"";
        } else {
            self.restrictionActive = YES;
            self.restrictionError = nil;
        }
        [self notifyVisibilityChanged];
    }];
    if (started) {
        // The activation is asynchronous; reflect intent immediately so the UI
        // does not flicker between states while the XPC round trip completes.
        self.restrictionActive = YES;
    } else {
        self.restrictionActive = NO;
    }
    [self notifyVisibilityChanged];
}

- (NSString *)statusDescription {
    NSUInteger hiddenCount = self.hiddenCount;
    NSUInteger appCount = self.lastScan.apps.count;
    NSUInteger itemCount = 0;
    for (MXAppMenuItems *app in self.lastScan.apps) {
        itemCount += app.items.count;
    }
    if (!self.privateAPIAvailable) {
        return @"Unsupported macOS build: the menu bar visibility API is unavailable.";
    }
    if (self.revealing) {
        return @"All menu bar items are visible (temporary reveal).";
    }
    if (!hiddenCount) {
        return @"Nothing is hidden. Turn apps off in Menu Bar Items to hide them.";
    }
    if (self.isHidingActive) {
        return [NSString stringWithFormat:@"Hiding %lu item%@. %lu apps / %lu items discovered.",
                (unsigned long)hiddenCount, hiddenCount == 1 ? @"" : @"s",
                (unsigned long)appCount, (unsigned long)itemCount];
    }
    return [NSString stringWithFormat:@"%lu item%@ marked hidden, but the restriction is not active.",
            (unsigned long)hiddenCount, hiddenCount == 1 ? @"" : @"s"];
}

- (void)notifyVisibilityChanged {
    [NSNotificationCenter.defaultCenter postNotificationName:MXVisibilityDidChangeNotification
                                                      object:self];
}

@end
