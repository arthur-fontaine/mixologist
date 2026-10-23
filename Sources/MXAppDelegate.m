#import "MXAppDelegate.h"
#import <Carbon/Carbon.h>
#import "MXHotKey.h"
#import "MXMenuBarScanner.h"
#import "MXSettingsWindowController.h"
#import "MXVisibilityController.h"

@interface MXAppDelegate ()
@property (nonatomic, strong) MXVisibilityController *visibilityController;
@property (nonatomic, strong) MXSettingsWindowController *settingsWindowController;
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong, nullable) MXHotKey *hotKey;
@property (nonatomic, strong, nullable) NSMenuItem *revealMenuItem;
@property (nonatomic) BOOL didShowSettings;
@end

@implementation MXAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
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

    [self.visibilityController start];
    [self updateMenuState];

    __weak typeof(self) weakSelf = self;
    [self.visibilityController refreshScanWithCompletion:^(MXScanResult *result) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            return;
        }
        [self updateMenuState];
        if (!result.isAccessibilityTrusted && !self.didShowSettings) {
            self.didShowSettings = YES;
            [self showSettings:nil];
        } else if (!self.visibilityController.store.hasShownWelcome) {
            self.visibilityController.store.hasShownWelcome = YES;
            [self showSettings:nil];
        }
    }];
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

- (void)updateMenuState {
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
