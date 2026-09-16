//
//  NickListController.h
//  Quassel for GNUstep
//
//  The channel member list. On iOS this was a modal / popover
//  (UserListTableViewController); on the desktop there is room to keep it
//  permanently visible as a third split-view pane.
//

#import <AppKit/AppKit.h>

@class QuasselCoreConnection;
@class MainWindowController;

@interface NickListController : NSObject <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, weak)   MainWindowController  *windowController;
@property (nonatomic, strong) QuasselCoreConnection *connection;

- (instancetype)initWithWindowController:(MainWindowController *)wc;

- (NSView *)view;

/// Show the members of this buffer. Non-channel buffers show an empty list.
- (void)showBufferId:(id)bufferId;

/// Re-read the member list for the buffer currently shown.
- (void)reload;

@end
