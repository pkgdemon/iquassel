//
//  QuasselAppDelegate.m
//  Quassel for GNUstep
//

#import "QuasselAppDelegate.h"
#import "MainWindowController.h"

@implementation QuasselAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
    [self buildMenu];

    self.windowController = [[MainWindowController alloc] init];
    [self.windowController showWindow:nil];
    [[self.windowController window] makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app
{
    return YES;
}

/// GNUstep has no main nib here (the UI is built programmatically), so the menu
/// is constructed by hand. Without it there is no way to quit the app.
- (void)buildMenu
{
    NSMenu *main = [[NSMenu alloc] initWithTitle:@"Quassel"];

    NSMenuItem *appItem = [[NSMenuItem alloc] initWithTitle:@"Quassel"
                                                     action:NULL
                                              keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Quassel"];
    [appMenu addItemWithTitle:@"Hide"
                       action:@selector(hide:)
                keyEquivalent:@"h"];
    [appMenu addItemWithTitle:@"Quit"
                       action:@selector(terminate:)
                keyEquivalent:@"q"];
    [appItem setSubmenu:appMenu];
    [main addItem:appItem];

    NSMenuItem *editItem = [[NSMenuItem alloc] initWithTitle:@"Edit"
                                                      action:NULL
                                               keyEquivalent:@""];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Cut"        action:@selector(cut:)        keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy"       action:@selector(copy:)       keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste"      action:@selector(paste:)      keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:)  keyEquivalent:@"a"];
    [editItem setSubmenu:editMenu];
    [main addItem:editItem];

    [NSApp setMainMenu:main];
}

@end
