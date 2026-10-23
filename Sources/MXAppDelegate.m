#import "MXAppDelegate.h"
#import <Carbon/Carbon.h>
#import "MXHotKey.h"
#import "MXMenuBarScanner.h"
#import "MXPermissions.h"
#import "Mixologist-Swift.h"
#import "MXVisibilityController.h"

@interface MXAppDelegate ()
@property (nonatomic, strong) MXVisibilityController *visibilityController;
@property (nonatomic, strong) MXSettingsWindowController *settingsWindowController;
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong, nullable) MXHotKey *hotKey;
@property (nonatomic, strong, nullable) NSMenuItem *revealMenuItem;
@property (nonatomic, strong, nullable) NSMenuItem *grantMenuItem;
@property (nonatomic, strong, nullable) NSMenuItem *grantSeparatorItem;
@property (nonatomic) BOOL didShowSettings;
@end

static NSString *const kMXShowSettingsNotification = @"dev.mixologist.Mixologist.showSettings";

@implementation MXAppDelegate

/// Two instances would install two restrictions whose allow lists intersect,
/// hiding items neither of them meant to hide. A second launch (from Finder,
/// another build folder, or a login item) hands over to the first one.
- (BOOL)handOffToRunningInstance {
    NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier;
    pid_t ownPID = NSProcessInfo.processInfo.processIdentifier;
    for (NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleIdentifier ?: @""]) {
        if (app.processIdentifier != ownPID && !app.isTerminated) {
            [NSDistributedNotificationCenter.defaultCenter postNotificationName:kMXShowSettingsNotification
                                                                         object:nil
                                                                       userInfo:nil
                                                                deliverImmediately:YES];
            return YES;
        }
    }
    return NO;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    if ([self handOffToRunningInstance]) {
        [NSApp terminate:nil];
        return;
    }
    [NSDistributedNotificationCenter.defaultCenter addObserver:self
                                                      selector:@selector(showSettings:)
                                                          name:kMXShowSettingsNotification
                                                        object:nil
                                            suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
    [MXPermissions.shared startWatching];
    [self installMainMenu];

    self.visibilityController = [[MXVisibilityController alloc] init];
    self.settingsWindowController = [[MXSettingsWindowController alloc] initWithController:self.visibilityController];

    [self installStatusItem];
    [self installHotKey];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(visibilityDidChange:)
                                               name:MXVisibilityDidChangeNotification
                                             object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(visibilityDidChange:)
                                               name:MXScanDidChangeNotification
                                             object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(accessibilityTrustDidChange:)
                                               name:MXAccessibilityTrustDidChangeNotification
                                             object:nil];

    [self.visibilityController start];
    [self updateMenuState];

    __weak typeof(self) weakSelf = self;
    [self.visibilityController refreshScanWithCompletion:^(MXScanResult *result) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            return;
        }
        [self updateMenuState];
        if (!MXPermissions.shared.isAccessibilityTrusted && !self.didShowSettings) {
            self.didShowSettings = YES;
            [self.settingsWindowController showPermissions];
            [self showSettings:nil];
        } else if (!self.visibilityController.store.hasShownWelcome) {
            self.visibilityController.store.hasShownWelcome = YES;
            [self showSettings:nil];
        }
    }];
}

/// Accessory apps get no main menu by default, which leaves ⌘W, ⌘Q and the
/// text-editing shortcuts dead whenever the settings window is key.
- (void)installMainMenu {
    NSMenu *mainMenu = [[NSMenu alloc] init];

    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Mixologist"];
    [appMenu addItemWithTitle:@"Settings…" action:@selector(showSettings:) keyEquivalent:@","].target = self;
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit Mixologist" action:@selector(terminate:) keyEquivalent:@"q"];
    [mainMenu addItemWithTitle:@"Mixologist" action:nil keyEquivalent:@""].submenu = appMenu;

    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    [mainMenu addItemWithTitle:@"Edit" action:nil keyEquivalent:@""].submenu = editMenu;

    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [windowMenu addItemWithTitle:@"Close" action:@selector(performClose:) keyEquivalent:@"w"];
    [windowMenu addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [mainMenu addItemWithTitle:@"Window" action:nil keyEquivalent:@""].submenu = windowMenu;
    NSApp.windowsMenu = windowMenu;

    NSApp.mainMenu = mainMenu;
}

- (void)installStatusItem {
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    NSStatusBarButton *button = self.statusItem.button;
    button.toolTip = @"Mixologist — menu bar organizer";

    NSImage *image = [NSImage imageWithSystemSymbolName:@"menubar.rectangle"
                               accessibilityDescription:@"Mixologist"];
    if (!image) {
        image = [NSImage imageWithSize:NSMakeSize(18, 18) flipped:NO drawingHandler:^BOOL(NSRect rect) {
            NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(rect, 2, 4)
                                                                xRadius:2
                                                                yRadius:2];
            path.lineWidth = 1.4;
            [NSColor.blackColor setStroke];
            [path stroke];
            [NSBezierPath strokeLineFromPoint:NSMakePoint(rect.origin.x + 3, rect.origin.y + 10)
                                      toPoint:NSMakePoint(rect.origin.x + rect.size.width - 3,
                                                          rect.origin.y + 10)];
            return YES;
        }];
    }
    image.template = YES;
    button.image = image;

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Mixologist"];
    self.grantMenuItem = [[NSMenuItem alloc] initWithTitle:@"Grant Accessibility Access…"
                                                    action:@selector(grantAccessibility:)
                                             keyEquivalent:@""];
    self.grantMenuItem.target = self;
    self.grantMenuItem.image = [NSImage imageWithSystemSymbolName:@"exclamationmark.triangle.fill"
                                         accessibilityDescription:nil];
    [menu addItem:self.grantMenuItem];
    self.grantSeparatorItem = [NSMenuItem separatorItem];
    [menu addItem:self.grantSeparatorItem];

    self.revealMenuItem = [[NSMenuItem alloc] initWithTitle:@"Reveal Hidden Items"
                                                     action:@selector(toggleReveal:)
                                              keyEquivalent:@""];
    self.revealMenuItem.target = self;
    [menu addItem:self.revealMenuItem];

    NSMenuItem *settings = [[NSMenuItem alloc] initWithTitle:@"Settings…"
                                                      action:@selector(showSettings:)
                                               keyEquivalent:@","];
    settings.target = self;
    [menu addItem:settings];

    NSMenuItem *rescan = [[NSMenuItem alloc] initWithTitle:@"Rescan Menu Bar"
                                                    action:@selector(rescan:)
                                             keyEquivalent:@""];
    rescan.target = self;
    [menu addItem:rescan];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *hideAll = [[NSMenuItem alloc] initWithTitle:@"Hide All Third-Party Apps"
                                                     action:@selector(hideAll:)
                                              keyEquivalent:@""];
    hideAll.target = self;
    [menu addItem:hideAll];

    NSMenuItem *unhideAll = [[NSMenuItem alloc] initWithTitle:@"Unhide All Apps"
                                                       action:@selector(unhideAll:)
                                                keyEquivalent:@""];
    unhideAll.target = self;
    [menu addItem:unhideAll];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *relaunch = [[NSMenuItem alloc] initWithTitle:@"Relaunch Mixologist"
                                                      action:@selector(relaunch:)
                                               keyEquivalent:@""];
    relaunch.target = self;
    [menu addItem:relaunch];

    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit Mixologist"
                                                  action:@selector(terminate:)
                                           keyEquivalent:@"q"];
    quit.target = NSApp;
    [menu addItem:quit];

    self.statusItem.menu = menu;
}

- (void)installHotKey {
    // Control-Option-Command-M: works even when Mixologist's own status item is
    // hidden by the restriction, and does not need Accessibility permission.
    UInt32 modifiers = controlKey | optionKey | cmdKey;
    self.hotKey = [[MXHotKey alloc] initWithKeyCode:46 modifiers:modifiers handler:^{
        [self toggleReveal:nil];
    }];
}

- (void)visibilityDidChange:(NSNotification *)notification {
    [self updateMenuState];
}

- (void)accessibilityTrustDidChange:(NSNotification *)notification {
    [self updateMenuState];
    // Bring the window back from System Settings so the grant visibly lands.
    if (MXPermissions.shared.isAccessibilityTrusted && self.settingsWindowController.window.isVisible) {
        [self showSettings:nil];
    }
}

- (void)updateMenuState {
    BOOL trusted = MXPermissions.shared.isAccessibilityTrusted;
    self.grantMenuItem.hidden = trusted;
    self.grantSeparatorItem.hidden = trusted;
    BOOL revealing = self.visibilityController.isRevealing;
    self.revealMenuItem.title = revealing ? @"Hide Revealed Items" : @"Reveal Hidden Items (15 s)";
    self.revealMenuItem.state = revealing ? NSControlStateValueOn : NSControlStateValueOff;
    self.statusItem.button.toolTip = self.visibilityController.statusDescription;
}

- (void)toggleReveal:(id)sender {
    if (self.visibilityController.isRevealing) {
        [self.visibilityController setRevealing:NO];
    } else {
        [self.visibilityController revealForSeconds:15];
    }
    [self updateMenuState];
}

- (void)showSettings:(id)sender {
    [self.settingsWindowController reloadData];
    [self.settingsWindowController showWindow:nil];
    [self.settingsWindowController.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)grantAccessibility:(id)sender {
    [MXPermissions.shared requestAccessibility];
}

- (void)relaunch:(id)sender {
    [MXPermissions relaunch];
}

- (void)rescan:(id)sender {
    [self.visibilityController refreshScanWithCompletion:^(MXScanResult *result) {
        [self updateMenuState];
    }];
}

- (void)hideAll:(id)sender {
    [self.visibilityController hideAllThirdPartyApps];
    [self updateMenuState];
}

- (void)unhideAll:(id)sender {
    [self.visibilityController showAllAppsPermanently];
    [self updateMenuState];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [NSDistributedNotificationCenter.defaultCenter removeObserver:self];
    [self.hotKey unregister];
    [self.visibilityController stop];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    [self showSettings:nil];
    return YES;
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

@end
