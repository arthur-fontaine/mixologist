#import "MXPrivateAPI.h"
#import <dlfcn.h>

// Private classes. Declared locally so the compiler knows the selectors; the
// implementations live in /System/Library/PrivateFrameworks/MenuBarClientCore.
@interface MBAssessmentModeConfiguration : NSObject
// `allowedSystemItems` is an array of NSNumber values, not strings. The
// underlying Swift type is [MBSystemItemIdentifier], whose Int raw values are
// 0...8. Passing strings silently maps every element to 0 (battery) through
// -integerValue, which hides Clock, Wi-Fi and Control Center.
- (instancetype)initWithAllowedSystemItems:(NSArray<NSNumber *> *)allowedSystemItems
                  allowedBundleIdentifiers:(NSArray<NSString *> *)allowedBundleIdentifiers;
@end

@interface MBAssessmentModeAssertion : NSObject
- (void)activateWithConfiguration:(MBAssessmentModeConfiguration *)configuration
                completionHandler:(void (^)(NSError *error))completionHandler;
- (void)invalidate;
@end

static NSString *const kFrameworkPath =
    @"/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore";

@interface MXAssessmentMode () {
    void *_handle;
    Class _configurationClass;
    Class _assertionClass;
    id _assertion;
}
@property (nonatomic, readwrite, getter=isActive) BOOL active;
@property (nonatomic, copy, readwrite, nullable) NSString *unavailableReason;
@end

@implementation MXAssessmentMode

+ (MXAssessmentMode *)shared {
    static MXAssessmentMode *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[MXAssessmentMode alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _handle = dlopen(kFrameworkPath.UTF8String, RTLD_NOW | RTLD_LOCAL);
        if (!_handle) {
            const char *error = dlerror();
            _unavailableReason = [NSString stringWithFormat:@"MenuBarClientCore could not be loaded: %s",
                                  error ?: "unknown error"];
            return self;
        }
        _configurationClass = NSClassFromString(@"MBAssessmentModeConfiguration");
        _assertionClass = NSClassFromString(@"MBAssessmentModeAssertion");
        if (!_configurationClass || !_assertionClass) {
            _unavailableReason = @"MenuBarClientCore does not expose the assessment-mode classes on this macOS version.";
        }
    }
    return self;
}

+ (NSArray<NSNumber *> *)allSystemItemRawValues {
    // MBSystemItemIdentifier cases, verified against the macOS 27
    // MenuBarClientCore Swift metadata:
    // 0 battery, 1 bluetooth, 2 clock, 3 displays, 4 keyboard, 5 volume,
    // 6 wifi, 7 screenMirroring, 8 primaryBentoBox (Control Center). The
    // `stringValue` getter and a live test (leaving out 8 hides Control
    // Center) both confirm this order.
    return @[@0, @1, @2, @3, @4, @5, @6, @7, @8];
}

- (BOOL)isAvailable {
    return _configurationClass != Nil && _assertionClass != Nil;
}

- (BOOL)activateWithAllowedSystemItems:(NSArray<NSNumber *> *)systemItems
               allowedBundleIdentifiers:(NSArray<NSString *> *)bundleIdentifiers
                            completion:(MXAssessmentCompletion)completion {
    if (!self.isAvailable) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"dev.mixologist.assessment"
                                                 code:1
                                             userInfo:@{NSLocalizedDescriptionKey:
                                                            self.unavailableReason ?: @"Assessment mode is unavailable."}];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
        }
        return NO;
    }

    // Release the previous assertion before installing a new allow list. The
    // visibility restriction server keys restrictions by assertion, so leaving
    // both alive can intersect their allow lists.
    [self invalidate];

    NSMutableArray<NSNumber *> *safeSystemItems = [NSMutableArray array];
    for (id item in systemItems ?: @[]) {
        if ([item isKindOfClass:[NSNumber class]]) {
            [safeSystemItems addObject:item];
        } else if ([item isKindOfClass:[NSString class]]) {
            [safeSystemItems addObject:@([(NSString *)item integerValue])];
        }
    }

    id configuration = [[_configurationClass alloc] initWithAllowedSystemItems:safeSystemItems
                                                       allowedBundleIdentifiers:bundleIdentifiers ?: @[]];
    if (!configuration) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"dev.mixologist.assessment"
                                                 code:2
                                             userInfo:@{NSLocalizedDescriptionKey:
                                                            @"MBAssessmentModeConfiguration returned nil."}];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
        }
        return NO;
    }

    id assertion = [[_assertionClass alloc] init];
    if (!assertion) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"dev.mixologist.assessment"
                                                 code:3
                                             userInfo:@{NSLocalizedDescriptionKey:
                                                            @"MBAssessmentModeAssertion returned nil."}];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
        }
        return NO;
    }

    _assertion = assertion;
    self.active = YES;

    __weak typeof(self) weakSelf = self;
    // The reply arrives on an XPC queue; callers update AppKit state.
    [(MBAssessmentModeAssertion *)assertion activateWithConfiguration:configuration
                                                   completionHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) {
                return;
            }
            // A late reply for an assertion that has since been replaced must
            // not tear down the one currently installed.
            if (self->_assertion != assertion) {
                return;
            }
            if (error) {
                self.active = NO;
                self->_assertion = nil;
            }
            if (completion) {
                completion(error);
            }
        });
    }];
    return YES;
}

- (void)invalidate {
    id assertion = _assertion;
    _assertion = nil;
    self.active = NO;
    if (assertion) {
        [(MBAssessmentModeAssertion *)assertion invalidate];
    }
}

- (void)dealloc {
    [self invalidate];
    if (_handle) {
        dlclose(_handle);
        _handle = NULL;
    }
}

@end
