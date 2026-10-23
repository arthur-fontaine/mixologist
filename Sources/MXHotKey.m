#import "MXHotKey.h"
#import <Carbon/Carbon.h>

static NSMutableDictionary<NSNumber *, MXHotKey *> *MXHotKeyRegistry(void) {
    static NSMutableDictionary *registry;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        registry = [NSMutableDictionary dictionary];
    });
    return registry;
}

@interface MXHotKey ()
@property (nonatomic) EventHotKeyRef hotKeyRef;
@property (nonatomic) EventHandlerRef eventHandlerRef;
@property (nonatomic) UInt32 hotKeyID;
@property (nonatomic, copy) void (^handler)(void);
@end

static OSStatus MXHotKeyHandler(EventHandlerCallRef nextHandler, EventRef event, void *userData) {
    EventHotKeyID hotKeyID;
    OSStatus status = GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID,
                                        NULL, sizeof(hotKeyID), NULL, &hotKeyID);
    if (status != noErr) {
        return status;
    }
    MXHotKey *hotKey = MXHotKeyRegistry()[@(hotKeyID.id)];
    if (hotKey.handler) {
        dispatch_async(dispatch_get_main_queue(), ^{
            hotKey.handler();
        });
    }
    return noErr;
}

@implementation MXHotKey

- (instancetype)initWithKeyCode:(UInt32)keyCode
                      modifiers:(UInt32)carbonModifiers
                        handler:(void (^)(void))handler {
    self = [super init];
    if (self) {
        _handler = [handler copy];
        static UInt32 nextID = 1;
        _hotKeyID = nextID++;

        EventTypeSpec eventType = {kEventClassKeyboard, kEventHotKeyPressed};
        InstallEventHandler(GetApplicationEventTarget(), MXHotKeyHandler, 1, &eventType,
                            NULL, &_eventHandlerRef);

        EventHotKeyID hotKeyID = {'MXHK', _hotKeyID};
        OSStatus status = RegisterEventHotKey(keyCode, carbonModifiers, hotKeyID,
                                              GetApplicationEventTarget(), 0, &_hotKeyRef);
        if (status != noErr) {
            NSLog(@"[Mixologist] Could not register hotkey (OSStatus %d)", (int)status);
            if (_eventHandlerRef) {
                RemoveEventHandler(_eventHandlerRef);
                _eventHandlerRef = NULL;
            }
            return nil;
        }
        MXHotKeyRegistry()[@(_hotKeyID)] = self;
    }
    return self;
}

- (void)unregister {
    if (self.hotKeyRef) {
        UnregisterEventHotKey(self.hotKeyRef);
        self.hotKeyRef = NULL;
    }
    if (self.eventHandlerRef) {
        RemoveEventHandler(self.eventHandlerRef);
        self.eventHandlerRef = NULL;
    }
    [MXHotKeyRegistry() removeObjectForKey:@(self.hotKeyID)];
}

- (void)dealloc {
    [self unregister];
}

@end
