#import <Cocoa/Cocoa.h>

// An accessory app does not have an Edit menu to dispatch these shortcuts.
static NSModalResponse RunEditableAlert(NSAlert *alert, BOOL secureEntry) {
    id monitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
        handler:^NSEvent *(NSEvent *event) {
            if (event.window != alert.window) return event;
            NSEventModifierFlags modifiers = event.modifierFlags &
                (NSEventModifierFlagCommand | NSEventModifierFlagShift |
                 NSEventModifierFlagOption | NSEventModifierFlagControl);
            if (modifiers != NSEventModifierFlagCommand &&
                modifiers != (NSEventModifierFlagCommand | NSEventModifierFlagShift)) return event;
            NSString *key = event.charactersIgnoringModifiers.lowercaseString;
            NSResponder *editor = alert.window.firstResponder;
            if (![editor isKindOfClass:NSTextView.class]) return event;
            NSTextView *text = (NSTextView *)editor;
            if ([key isEqualToString:@"z"]) {
                NSUndoManager *undo = text.undoManager;
                if (modifiers & NSEventModifierFlagShift) [undo redo];
                else [undo undo];
                return nil;
            }
            if (modifiers != NSEventModifierFlagCommand) return event;
            if (secureEntry && ([key isEqualToString:@"c"] || [key isEqualToString:@"x"])) return nil;
            if ([key isEqualToString:@"v"]) [text paste:nil];
            else if ([key isEqualToString:@"a"]) [text selectAll:nil];
            else if ([key isEqualToString:@"c"]) [text copy:nil];
            else if ([key isEqualToString:@"x"]) [text cut:nil];
            else return event;
            return nil;
        }];
    NSModalResponse response = [alert runModal];
    [NSEvent removeMonitor:monitor];
    if (response == NSAlertFirstButtonReturn) [alert.window makeFirstResponder:nil];
    return response;
}
