#import <Cocoa/Cocoa.h>
#import "MXAppDelegate.h"
#import "MXMenuBarScanner.h"
#import "MXPrivateAPI.h"
#import "MXVisibilityController.h"
#import "MXVisibilityPlan.h"

static NSString *MXValueForOption(NSArray<NSString *> *arguments, NSString *option) {
    NSUInteger index = [arguments indexOfObject:option];
    if (index == NSNotFound || index + 1 >= arguments.count) {
        return nil;
    }
    return arguments[index + 1];
}

static NSSet<NSString *> *MXBundleSetFromList(NSString *list) {
    NSMutableSet *set = [NSMutableSet set];
    for (NSString *part in [list componentsSeparatedByString:@","]) {
        NSString *trimmed = [part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmed.length) {
            [set addObject:trimmed];
        }
    }
    return set;
}

static int MXRunDiagnose(void) {
    printf("Mixologist diagnostics\n");
    printf("=====================\n");
    printf("macOS: %s\n", NSProcessInfo.processInfo.operatingSystemVersionString.UTF8String);
    printf("Bundle identifier: %s\n", (NSBundle.mainBundle.bundleIdentifier ?: @"(none)").UTF8String);
    printf("Executable: %s\n", NSBundle.mainBundle.executablePath.UTF8String ?: "(unknown)");
    printf("Accessibility: %s\n", [MXMenuBarScanner accessibilityTrustedWithPrompt:NO] ? "granted" : "not granted");
    MXAssessmentMode *assessment = MXAssessmentMode.shared;
    printf("Assessment API: %s", assessment.isAvailable ? "available" : "unavailable");
    if (!assessment.isAvailable) {
        printf(" (%s)", (assessment.unavailableReason ?: @"unknown").UTF8String);
    }
    printf("\n");

    MXScanResult *scan = [[MXMenuBarScanner alloc] scan];
    printf("Scan: %.2f s, %lu apps with items, %lu third-party bundle IDs, %lu system item IDs\n",
           scan.duration, (unsigned long)scan.apps.count,
           (unsigned long)scan.thirdPartyBundleIdentifiers.count,
           (unsigned long)scan.systemItemIdentifiers.count);
    for (MXAppMenuItems *app in scan.apps) {
        printf("  %s%s <%s> %lu item(s)\n",
               app.appName.UTF8String,
               app.isSystemApp ? " [system]" : "",
               app.bundleIdentifier.UTF8String,
               (unsigned long)app.items.count);
        for (MXMenuItem *item in app.items) {
            printf("    - %s [%s] x=%.0f w=%.0f\n",
                   item.title.UTF8String,
                   item.identifier.UTF8String,
                   item.frame.origin.x,
                   item.frame.size.width);
        }
    }
    printf("System item identifiers:\n");
    for (NSString *identifier in scan.systemItemIdentifiers) {
        printf("  %s\n", identifier.UTF8String);
    }
    printf("Third-party bundle identifiers:\n");
    for (NSString *identifier in scan.thirdPartyBundleIdentifiers) {
        printf("  %s\n", identifier.UTF8String);
    }
    NSArray *hidden = [NSUserDefaults.standardUserDefaults arrayForKey:@"hiddenBundleIdentifiers"] ?: @[];
    printf("Hidden bundle identifiers in preferences: %s\n", [hidden componentsJoinedByString:@", "].UTF8String);
    return 0;
}

static int MXRunScan(void) {
    MXScanResult *scan = [[MXMenuBarScanner alloc] scan];
    NSMutableArray *apps = [NSMutableArray array];
    for (MXAppMenuItems *app in scan.apps) {
        NSMutableArray *items = [NSMutableArray array];
        for (MXMenuItem *item in app.items) {
            [items addObject:@{
                @"title": item.title ?: @"",
                @"identifier": item.identifier ?: @"",
                @"help": item.help ?: @"",
                @"x": @(item.frame.origin.x),
                @"y": @(item.frame.origin.y),
                @"width": @(item.frame.size.width),
                @"height": @(item.frame.size.height),
                @"system": @(item.isSystemItem),
            }];
        }
        [apps addObject:@{
            @"name": app.appName ?: @"",
            @"bundleIdentifier": app.bundleIdentifier ?: @"",
            @"path": app.bundlePath ?: @"",
            @"system": @(app.isSystemApp),
            @"items": items,
        }];
    }
    NSDictionary *json = @{
        @"accessibilityTrusted": @(scan.isAccessibilityTrusted),
        @"systemItemIdentifiers": scan.systemItemIdentifiers ?: @[],
        @"thirdPartyBundleIdentifiers": scan.thirdPartyBundleIdentifiers ?: @[],
        @"runningBundleIdentifiers": scan.runningBundleIdentifiers ?: @[],
        @"apps": apps,
    };
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:json
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                     error:&error];
    if (!data) {
        fprintf(stderr, "Could not encode scan: %s\n", error.localizedDescription.UTF8String);
        return 2;
    }
    fwrite(data.bytes, 1, data.length, stdout);
    printf("\n");
    return 0;
}

static int MXRunHide(NSArray<NSString *> *arguments) {
    NSString *list = MXValueForOption(arguments, @"--hide");
    if (!list) {
        fprintf(stderr, "Usage: --hide com.example.app[,com.example.two] [--seconds N]\n");
        return 2;
    }
    NSSet *hidden = MXBundleSetFromList(list);
    NSInteger seconds = 5;
    NSString *secondsValue = MXValueForOption(arguments, @"--seconds");
    if (secondsValue) {
        seconds = secondsValue.integerValue;
    }
    if (seconds < 1) {
        seconds = 1;
    }

    MXScanResult *scan = [[MXMenuBarScanner alloc] scan];
    MXVisibilityPlan *plan = [MXVisibilityPlan planWithScannedBundleIdentifiers:
                                  [NSSet setWithArray:scan.thirdPartyBundleIdentifiers]
                                             runningBundleIdentifiers:
                                  [NSSet setWithArray:scan.runningBundleIdentifiers]
                                                   hiddenBundleIdentifiers:hidden
                                                         hiddenSystemItems:[NSSet set]
                                                  ownBundleIdentifier:NSBundle.mainBundle.bundleIdentifier];
    printf("Accessibility: %s\n", scan.isAccessibilityTrusted ? "granted" : "not granted");
    printf("Plan: %s\n", plan.description.UTF8String);
    printf("Hidden: %s\n", [[hidden.allObjects sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@", "].UTF8String);

    // Diagnostic overrides, used to isolate how the private API matches allowed
    // bundles and system items. Not part of the normal app flow.
    NSArray<NSString *> *allowedBundles = plan.allowedBundleIdentifiers;
    NSString *allowOverride = MXValueForOption(arguments, @"--allow");
    if (allowOverride) {
        NSMutableSet *overridden = [MXBundleSetFromList(allowOverride) mutableCopy];
        if (NSBundle.mainBundle.bundleIdentifier.length) {
            [overridden addObject:NSBundle.mainBundle.bundleIdentifier];
        }
        [overridden addObjectsFromArray:@[
            @"com.apple.controlcenter",
            @"com.apple.systemuiserver",
            @"com.apple.MenuBarAgent",
        ]];
        allowedBundles = [overridden.allObjects sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    }

    NSArray<NSNumber *> *systemItems = plan.allowedSystemItemRawValues;
    NSString *systemOverride = MXValueForOption(arguments, @"--system-items");
    if (systemOverride) {
        NSMutableArray<NSNumber *> *values = [NSMutableArray array];
        for (NSString *part in [systemOverride componentsSeparatedByString:@","]) {
            NSString *trimmed = [part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (trimmed.length) {
                [values addObject:@(trimmed.integerValue)];
            }
        }
        systemItems = values;
    }

    printf("Allowed bundles: %s\n", [allowedBundles componentsJoinedByString:@", "].UTF8String);
    printf("Allowed system item raw values: %s\n", [[systemItems valueForKey:@"description"] componentsJoinedByString:@", "].UTF8String);

    if (!MXAssessmentMode.shared.isAvailable) {
        fprintf(stderr, "Assessment API unavailable: %s\n",
                (MXAssessmentMode.shared.unavailableReason ?: @"unknown").UTF8String);
        return 3;
    }

    __block BOOL finished = NO;
    __block NSError *activationError = nil;
    BOOL started = [MXAssessmentMode.shared activateWithAllowedSystemItems:systemItems
                                                   allowedBundleIdentifiers:allowedBundles
                                                                completion:^(NSError *error) {
        activationError = error;
        finished = YES;
    }];
    if (!started) {
        fprintf(stderr, "Activation was not started.\n");
        return 4;
    }

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while ([deadline timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
    printf("Activation callback: %s%s\n", finished ? "received" : "not received",
           activationError ? [NSString stringWithFormat:@" (%@)", activationError.localizedDescription].UTF8String : "");
    [MXAssessmentMode.shared invalidate];
    printf("Restriction released.\n");
    return activationError ? 5 : 0;
}

static BOOL MXCheck(BOOL condition, NSString *message) {
    printf("%s %s\n", condition ? "PASS" : "FAIL", message.UTF8String);
    return condition;
}

static int MXRunSelfTest(void) {
    BOOL ok = YES;
    NSSet *scanned = [NSSet setWithArray:@[@"com.a", @"com.b"]];
    NSSet *running = [NSSet setWithArray:@[@"com.a", @"com.b", @"com.c"]];
    NSSet *hidden = [NSSet setWithArray:@[@"com.b"]];
    MXVisibilityPlan *plan = [MXVisibilityPlan planWithScannedBundleIdentifiers:scanned
                                                       runningBundleIdentifiers:running
                                                             hiddenBundleIdentifiers:hidden
                                                                   hiddenSystemItems:[NSSet set]
                                                                    ownBundleIdentifier:@"dev.mixologist.Mixologist"];
    ok &= MXCheck(plan.shouldRestrict, @"empty allow list is not used when something is hidden");
    ok &= MXCheck([plan.allowedBundleIdentifiers containsObject:@"com.a"], @"scanned visible app is allowed");
    ok &= MXCheck(![plan.allowedBundleIdentifiers containsObject:@"com.b"], @"hidden app is excluded");
    ok &= MXCheck([plan.allowedBundleIdentifiers containsObject:@"dev.mixologist.Mixologist"], @"own bundle is always allowed");
    ok &= MXCheck(plan.allowedSystemItemRawValues.count == 9, @"all nine system items are allowed");
    ok &= MXCheck([plan.allowedSystemItemRawValues.firstObject isEqual:@0] &&
                  [plan.allowedSystemItemRawValues.lastObject isEqual:@8], @"system item raw values cover 0...8");
    ok &= MXCheck(![plan.allowedBundleIdentifiers containsObject:@""], @"empty bundle identifiers are filtered");

    MXVisibilityPlan *empty = [MXVisibilityPlan planWithScannedBundleIdentifiers:scanned
                                                         runningBundleIdentifiers:running
                                                               hiddenBundleIdentifiers:[NSSet set]
                                                                     hiddenSystemItems:[NSSet set]
                                                                      ownBundleIdentifier:@"dev.mixologist.Mixologist"];
    ok &= MXCheck(!empty.shouldRestrict, @"nothing hidden means no restriction");
    ok &= MXCheck(empty.allowedSystemItemRawValues.count == 9, @"system items are always allowed");

    MXVisibilityPlan *fallback = [MXVisibilityPlan planWithScannedBundleIdentifiers:[NSSet set]
                                                          runningBundleIdentifiers:[NSSet set]
                                                                hiddenBundleIdentifiers:[NSSet setWithObject:@"com.hidden"]
                                                                      hiddenSystemItems:[NSSet set]
                                                                       ownBundleIdentifier:nil];
    ok &= MXCheck(fallback.shouldRestrict, @"hidden set alone activates restriction");
    ok &= MXCheck(fallback.allowedSystemItemRawValues.count == 9, @"system items are allowed without a scan");
    ok &= MXCheck(![fallback.allowedBundleIdentifiers containsObject:@"com.hidden"], @"hidden app excluded without a scan");

    MXVisibilityPlan *noClock = [MXVisibilityPlan planWithScannedBundleIdentifiers:scanned
                                                          runningBundleIdentifiers:running
                                                                hiddenBundleIdentifiers:[NSSet setWithObject:@"com.apple.systemuiserver"]
                                                                      hiddenSystemItems:[NSSet setWithObject:@2]
                                                                       ownBundleIdentifier:nil];
    ok &= MXCheck(noClock.shouldRestrict, @"a hidden Apple module alone activates restriction");
    ok &= MXCheck(noClock.allowedSystemItemRawValues.count == 8 &&
                  ![noClock.allowedSystemItemRawValues containsObject:@2], @"hidden Apple module is left out");
    ok &= MXCheck(![noClock.allowedBundleIdentifiers containsObject:@"com.apple.systemuiserver"],
                  @"Apple bundles can be hidden");
    ok &= MXCheck([noClock.allowedBundleIdentifiers containsObject:@"com.apple.MenuBarAgent"],
                  @"MenuBarAgent is always allowed");
    ok &= MXCheck([[MXVisibilityPlan systemItemRawValueForItemIdentifier:@"com.apple.menuextra.clock"] isEqual:@2] &&
                  [[MXVisibilityPlan systemItemRawValueForItemIdentifier:@"com.apple.menuextra.wifi"] isEqual:@6] &&
                  [[MXVisibilityPlan systemItemRawValueForItemIdentifier:@"com.apple.menuextra.controlcenter"] isEqual:@7] &&
                  [MXVisibilityPlan systemItemRawValueForItemIdentifier:@"com.example.item"] == nil,
                  @"Apple module identifiers map to raw values");

    // Regression: the custom -setRevealing: used to assign self.revealing and
    // recurse until the stack overflowed, crashing on every Reveal click.
    MXVisibilityController *controller = [[MXVisibilityController alloc] init];
    NSSet<NSString *> *previousHidden = controller.store.hiddenBundleIdentifiers;
    controller.store.hiddenBundleIdentifiers = [NSSet set];
    [controller setRevealing:YES];
    ok &= MXCheck(controller.isRevealing, @"revealing state can be enabled");
    [controller setRevealing:NO];
    ok &= MXCheck(!controller.isRevealing, @"revealing state can be disabled without recursion");
    controller.store.hiddenBundleIdentifiers = previousHidden;

    ok &= MXCheck(ok, @"all visibility-plan tests passed");
    return ok ? 0 : 1;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
        if ([arguments containsObject:@"--diagnose"]) {
            return MXRunDiagnose();
        }
        if ([arguments containsObject:@"--scan"]) {
            return MXRunScan();
        }
        if ([arguments containsObject:@"--self-test"]) {
            return MXRunSelfTest();
        }
        if ([arguments containsObject:@"--hide"]) {
            return MXRunHide(arguments);
        }

        NSApplication *application = [NSApplication sharedApplication];
        [application setActivationPolicy:NSApplicationActivationPolicyAccessory];
        static MXAppDelegate *delegate;
        delegate = [[MXAppDelegate alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
