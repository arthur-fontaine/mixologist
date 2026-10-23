#import "MXPermissions.h"
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>

NSNotificationName const MXAccessibilityTrustDidChangeNotification = @"MXAccessibilityTrustDidChangeNotification";

static NSString *const kMXWasAccessibilityTrustedKey = @"wasAccessibilityTrusted";

@interface MXPermissions ()
@property (nonatomic, readwrite, getter=isAccessibilityTrusted) BOOL accessibilityTrusted;
@property (nonatomic, strong, nullable) NSTimer *pollTimer;
@property (nonatomic) BOOL promptedThisLaunch;
@property (nonatomic) BOOL watching;
@end

@implementation MXPermissions

+ (MXPermissions *)shared {
    static MXPermissions *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[MXPermissions alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _accessibilityTrusted = AXIsProcessTrusted();
        [self rememberTrust];
    }
    return self;
}

- (BOOL)accessibilityWasLost {
    return !self.accessibilityTrusted &&
           [NSUserDefaults.standardUserDefaults boolForKey:kMXWasAccessibilityTrustedKey];
}

- (void)rememberTrust {
    if (self.accessibilityTrusted) {
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:kMXWasAccessibilityTrustedKey];
    }
}

- (void)startWatching {
    if (self.watching) {
        return;
    }
    self.watching = YES;
    // Posted whenever the Accessibility list changes, slightly before the new
    // state is readable — hence the delay, and the poll as a fallback.
    [NSDistributedNotificationCenter.defaultCenter addObserver:self
                                                      selector:@selector(accessibilityListDidChange:)
                                                          name:@"com.apple.accessibility.api"
                                                        object:nil
                                            suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(checkTrust)
                                               name:NSApplicationDidBecomeActiveNotification
                                             object:nil];
    [self updatePolling];
}

- (void)accessibilityListDidChange:(NSNotification *)notification {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self checkTrust];
    });
}

- (void)checkTrust {
    BOOL trusted = AXIsProcessTrusted();
    if (trusted == self.accessibilityTrusted) {
        return;
    }
    self.accessibilityTrusted = trusted;
    [self rememberTrust];
    [self updatePolling];
    [NSNotificationCenter.defaultCenter postNotificationName:MXAccessibilityTrustDidChangeNotification
                                                      object:self];
}

- (void)updatePolling {
    if (self.accessibilityTrusted) {
        [self.pollTimer invalidate];
        self.pollTimer = nil;
        return;
    }
    if (self.pollTimer) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
        [weakSelf checkTrust];
    }];
}

- (void)requestAccessibility {
    if (!self.promptedThisLaunch) {
        self.promptedThisLaunch = YES;
        // The prompting variant is what adds Mixologist to the list in System
        // Settings; without it the user would have to add the app by hand.
        NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES};
        if (AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options)) {
            [self checkTrust];
            return;
        }
    }
    [self openAccessibilitySettings];
}

- (void)openAccessibilitySettings {
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
    if (url) {
        [NSWorkspace.sharedWorkspace openURL:url];
    }
}

- (void)resetAccessibilityWithCompletion:(void (^)(BOOL))completion {
    NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier;
    if (!bundleIdentifier.length) {
        if (completion) {
            completion(NO);
        }
        return;
    }
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/tccutil"];
    task.arguments = @[@"reset", @"Accessibility", bundleIdentifier];
    task.standardOutput = NSFileHandle.fileHandleWithNullDevice;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;
    __weak typeof(self) weakSelf = self;
    task.terminationHandler = ^(NSTask *finished) {
        BOOL success = finished.terminationStatus == 0;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (success) {
                [NSUserDefaults.standardUserDefaults removeObjectForKey:kMXWasAccessibilityTrustedKey];
                self.promptedThisLaunch = NO;
                [self checkTrust];
                [NSNotificationCenter.defaultCenter postNotificationName:MXAccessibilityTrustDidChangeNotification
                                                                  object:self];
                [self requestAccessibility];
            }
            if (completion) {
                completion(success);
            }
        });
    };
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        NSLog(@"[Mixologist] tccutil failed to start: %@", error);
        if (completion) {
            completion(NO);
        }
    }
}

+ (void)relaunch {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
    // $0 is our pid and $1 the bundle path; waiting for the exit keeps the new
    // copy from tripping the single-instance check.
    task.arguments = @[
        @"-c",
        @"while kill -0 \"$0\" 2>/dev/null; do sleep 0.1; done; exec /usr/bin/open \"$1\"",
        [NSString stringWithFormat:@"%d", NSProcessInfo.processInfo.processIdentifier],
        NSBundle.mainBundle.bundlePath,
    ];
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        NSLog(@"[Mixologist] Could not relaunch: %@", error);
        return;
    }
    [NSApp terminate:nil];
}

@end
