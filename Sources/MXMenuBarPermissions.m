#import "MXMenuBarPermissions.h"
#import <dlfcn.h>

static NSString *const kMXJournalKey = @"menuBarPermissionJournal";
static NSString *const kMXErrorDomain = @"dev.mixologist.permission";
static CFStringRef const kMXAppGroup = CFSTR("group.com.apple.controlcenter");
static CFStringRef const kMXTrackedApplicationsKey = CFSTR("trackedApplications");

// Private CoreFoundation calls that address an app group's preferences through
// cfprefsd's container source. That is the source System Settings writes and
// MenuBarAgent observes; writing the same plist by path changes the file but
// never reaches MenuBarAgent.
typedef CFPropertyListRef (*MXCopyWithContainer)(CFStringRef, CFStringRef, CFStringRef, CFStringRef, CFStringRef);
typedef void (*MXSetWithContainer)(CFStringRef, CFPropertyListRef, CFStringRef, CFStringRef, CFStringRef, CFStringRef);
typedef Boolean (*MXSynchronizeWithContainer)(CFStringRef, CFStringRef, CFStringRef, CFStringRef);

static NSString *MXRecordBundleIdentifier(id record) {
    if (![record isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    id bundle = record[@"location"][@"bundle"];
    id identifier = [bundle isKindOfClass:[NSDictionary class]] ? bundle[@"_0"] : nil;
    return [identifier isKindOfClass:[NSString class]] ? identifier : nil;
}

@implementation MXPermissionReconciliation

+ (instancetype)reconcileEntries:(NSArray *)entries journal:(NSSet<NSString *> *)journal target:(NSSet<NSString *> *)target {
    MXPermissionReconciliation *result = [[MXPermissionReconciliation alloc] init];
    NSMutableArray *updated = [NSMutableArray arrayWithCapacity:entries.count];
    NSMutableSet<NSString *> *newJournal = [NSMutableSet set];
    BOOL changes = NO;

    // Swift encodes [Location: TrackedApplication] as a flat [key, value, …] array.
    for (NSUInteger index = 0; index < entries.count; index++) {
        id entry = entries[index];
        NSString *bundleIdentifier = index % 2 == 1 ? MXRecordBundleIdentifier(entry) : nil;
        if (!bundleIdentifier) {
            [updated addObject:entry];
            continue;
        }
        BOOL allowed = [entry[@"isAllowed"] boolValue];
        BOOL ours = [journal containsObject:bundleIdentifier];
        BOOL wanted = [target containsObject:bundleIdentifier];
        NSMutableDictionary *record = [entry mutableCopy];
        if (wanted && allowed) {
            record[@"isAllowed"] = @NO;
            [newJournal addObject:bundleIdentifier];
            changes = YES;
        } else if (wanted && ours) {
            [newJournal addObject:bundleIdentifier];
        } else if (!wanted && ours && !allowed) {
            record[@"isAllowed"] = @YES;
            changes = YES;
        }
        [updated addObject:record];
    }
    // Journaled apps whose entry is gone (System Settings prunes the list) have
    // nothing left to restore.
    if (![newJournal isEqualToSet:journal]) {
        changes = YES;
    }

    result->_entries = updated;
    result->_journal = newJournal;
    result->_changes = changes;
    return result;
}

@end

@implementation MXMenuBarPermissions {
    MXCopyWithContainer _copy;
    MXSetWithContainer _set;
    MXSynchronizeWithContainer _synchronize;
}

+ (MXMenuBarPermissions *)shared {
    static MXMenuBarPermissions *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[MXMenuBarPermissions alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _copy = (MXCopyWithContainer)dlsym(RTLD_DEFAULT, "_CFPreferencesCopyValueWithContainer");
        _set = (MXSetWithContainer)dlsym(RTLD_DEFAULT, "_CFPreferencesSetValueWithContainer");
        _synchronize = (MXSynchronizeWithContainer)dlsym(RTLD_DEFAULT, "_CFPreferencesSynchronizeWithContainer");
    }
    return self;
}

- (BOOL)isAvailable {
    return _copy && _set && _synchronize;
}

- (CFStringRef)container {
    NSString *path = [NSFileManager.defaultManager.homeDirectoryForCurrentUser
        URLByAppendingPathComponent:@"Library/Group Containers/group.com.apple.controlcenter"].path;
    return (__bridge CFStringRef)path;
}

- (NSSet<NSString *> *)journal {
    NSMutableSet<NSString *> *journal = [NSMutableSet set];
    for (id value in [NSUserDefaults.standardUserDefaults arrayForKey:kMXJournalKey]) {
        if ([value isKindOfClass:[NSString class]]) {
            [journal addObject:value];
        }
    }
    return journal;
}

- (void)saveJournal:(NSSet<NSString *> *)journal {
    NSArray *sorted = [journal.allObjects sortedArrayUsingSelector:@selector(compare:)];
    [NSUserDefaults.standardUserDefaults setObject:sorted forKey:kMXJournalKey];
    // Forced to disk before the approvals change: a crash in between must not
    // leave an app turned off that no later launch knows to turn back on.
    [NSUserDefaults.standardUserDefaults synchronize];
}

- (BOOL)fail:(NSString *)message error:(NSError **)error {
    if (error) {
        *error = [NSError errorWithDomain:kMXErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
    }
    return NO;
}

- (BOOL)turnOffExactly:(NSSet<NSString *> *)bundleIdentifiers error:(NSError **)error {
    NSSet<NSString *> *journal = self.journal;
    if (!bundleIdentifiers.count && !journal.count) {
        return YES;
    }
    if (!self.isAvailable) {
        return [self fail:@"This version of macOS doesn't let Mixologist change menu bar permissions." error:error];
    }

    // Always read fresh: System Settings rewrites and prunes this list itself.
    NSData *data = CFBridgingRelease(_copy(kMXTrackedApplicationsKey, kMXAppGroup, kCFPreferencesCurrentUser,
                                           kCFPreferencesAnyHost, self.container));
    if (![data isKindOfClass:[NSData class]]) {
        return [self fail:@"Couldn't read the Allow in the Menu Bar settings." error:error];
    }
    NSArray *entries = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
    if (![entries isKindOfClass:[NSArray class]] || entries.count % 2) {
        return [self fail:@"The Allow in the Menu Bar settings have an unexpected format." error:error];
    }

    MXPermissionReconciliation *result = [MXPermissionReconciliation reconcileEntries:entries
                                                                              journal:journal
                                                                               target:bundleIdentifiers];
    if (!result.hasChanges) {
        return YES;
    }
    [self saveJournal:[journal setByAddingObjectsFromSet:result.journal]];
    NSData *updated = [NSPropertyListSerialization dataWithPropertyList:result.entries
                                                                 format:NSPropertyListBinaryFormat_v1_0
                                                                options:0
                                                                  error:NULL];
    if (!updated) {
        return [self fail:@"Couldn't encode the Allow in the Menu Bar settings." error:error];
    }
    _set(kMXTrackedApplicationsKey, (__bridge CFDataRef)updated, kMXAppGroup, kCFPreferencesCurrentUser,
         kCFPreferencesAnyHost, self.container);
    if (!_synchronize(kMXAppGroup, kCFPreferencesCurrentUser, kCFPreferencesAnyHost, self.container)) {
        return [self fail:@"Couldn't save the Allow in the Menu Bar settings." error:error];
    }
    [self saveJournal:result.journal];
    return YES;
}

@end
