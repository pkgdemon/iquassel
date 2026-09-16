//
//  MainWindowController.m
//  Quassel for GNUstep
//

#import "MainWindowController.h"
#import "BufferListController.h"
#import "ChatViewController.h"
#import "NickListController.h"

#import "QuasselCoreConnection.h"
#import "BufferInfo.h"
#import "SignedId.h"
#import "Message.h"
#import "AppState.h"

// Layout is done with explicit frames and autoresizing masks rather than
// NSStackView / Auto Layout: gnustep-gui's NSStackView lays out in fixed thirds
// and its constraint engine is new and lightly tested.
static const CGFloat kSidebarWidth  = 220.0;
static const CGFloat kNickListWidth = 160.0;
static const CGFloat kPad          = 16.0;
static const CGFloat kFieldH       = 24.0;
static const CGFloat kRowGap       = 10.0;

@interface MainWindowController ()
{
    NSSplitView    *_split;
    NSView         *_contentBox;      // right-hand pane; holds one child at a time

    // connection screens
    NSView         *_loginView;
    NSTextField    *_hostField;
    NSTextField    *_portField;
    NSTextField    *_userField;
    NSSecureTextField *_passField;
    NSButton       *_connectButton;

    NSView         *_statusView;
    NSTextField    *_statusLabel;
    NSButton       *_retryButton;

    NSToolbar      *_toolbar;

    NSView         *_chatContainer;
    BOOL            _nickListVisible;
}
@property (nonatomic, assign) QuasselUIState state;
@property (nonatomic, strong) BufferListController *bufferList;
@property (nonatomic, strong) ChatViewController   *chat;
@property (nonatomic, strong) NickListController   *nickList;
@end


@implementation MainWindowController

- (instancetype)init
{
    NSRect frame = NSMakeRect(0, 0, 1000, 640);
    NSUInteger style = NSTitledWindowMask | NSClosableWindowMask
                     | NSMiniaturizableWindowMask | NSResizableWindowMask;

    NSWindow *w = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:style
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    [w setTitle:@"Quassel"];
    [w setMinSize:NSMakeSize(640, 400)];
    [w center];

    if ((self = [super initWithWindow:w])) {
        [self buildInterface];
        [self showState:QuasselUIStateLogin];
    }
    return self;
}

#pragma mark - Interface construction

- (void)buildInterface
{
    NSView *content = [self.window contentView];
    NSRect  b       = [content bounds];

    _split = [[NSSplitView alloc] initWithFrame:b];
    [_split setVertical:YES];              // side-by-side panes
    [_split setDividerStyle:NSSplitViewDividerStyleThin];
    [_split setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    // --- left: buffer list ---
    self.bufferList = [[BufferListController alloc] initWithWindowController:self];
    NSView *sidebar = [self.bufferList view];
    [sidebar setFrame:NSMakeRect(0, 0, kSidebarWidth, b.size.height)];

    // --- right: swappable content ---
    _contentBox = [[NSView alloc] initWithFrame:
                   NSMakeRect(0, 0, b.size.width - kSidebarWidth, b.size.height)];
    [_contentBox setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    [_split addSubview:sidebar];
    [_split addSubview:_contentBox];
    [content addSubview:_split];

    // gnustep-gui's NSSplitView does not derive pane widths from subview frames,
    // so place the divider explicitly.
    [_split adjustSubviews];
    [_split setPosition:kSidebarWidth ofDividerAtIndex:0];

    // The member list sits beside the chat log in a plain container rather than
    // as a third split pane: gnustep-gui's NSSplitView gives a third subview
    // zero width regardless of its frame or the delegate's sizing answers.
    // Explicit frames plus autoresizing masks are deterministic here.
    self.nickList = [[NickListController alloc] initWithWindowController:self];

    [self buildLoginView];
    [self buildStatusView];

    self.chat = [[ChatViewController alloc] initWithWindowController:self];
    [self buildChatContainer];

    [self buildToolbar];
}

- (void)buildToolbar
{
    _toolbar = [[NSToolbar alloc] initWithIdentifier:@"QuasselToolbar"];
    [_toolbar setDelegate:(id)self];
    [_toolbar setAllowsUserCustomization:NO];
    [_toolbar setDisplayMode:NSToolbarDisplayModeIconAndLabel];
    [self.window setToolbar:_toolbar];
}

/// A labelled text field plus its caption, stacked top-down from `y`.
- (NSTextField *)addFieldTo:(NSView *)parent
                      label:(NSString *)label
                      value:(NSString *)value
                     secure:(BOOL)secure
                          y:(CGFloat *)y
                      width:(CGFloat)width
{
    NSTextField *caption = [[NSTextField alloc] initWithFrame:
                            NSMakeRect(kPad, *y, width, 16)];
    [caption setStringValue:label];
    [caption setBezeled:NO];
    [caption setDrawsBackground:NO];
    [caption setEditable:NO];
    [caption setSelectable:NO];
    [caption setFont:[NSFont systemFontOfSize:11]];
    [caption setTextColor:[NSColor darkGrayColor]];
    [parent addSubview:caption];
    *y -= (kFieldH + 2);

    NSTextField *field = secure
        ? [[NSSecureTextField alloc] initWithFrame:NSMakeRect(kPad, *y, width, kFieldH)]
        : [[NSTextField alloc]       initWithFrame:NSMakeRect(kPad, *y, width, kFieldH)];
    [field setStringValue:value ?: @""];
    [field setBezeled:YES];
    [field setEditable:YES];
    [parent addSubview:field];
    *y -= (kFieldH + kRowGap + 6);

    return field;
}

- (void)buildLoginView
{
    NSRect box = [_contentBox bounds];
    _loginView = [[NSView alloc] initWithFrame:box];
    [_loginView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    CGFloat width = 260;
    CGFloat y     = box.size.height - 90;

    NSTextField *title = [[NSTextField alloc] initWithFrame:
                          NSMakeRect(kPad, y + 34, width, 24)];
    [title setStringValue:@"Connect to a Quassel core"];
    [title setBezeled:NO];
    [title setDrawsBackground:NO];
    [title setEditable:NO];
    [title setSelectable:NO];
    [title setFont:[NSFont boldSystemFontOfSize:15]];
    [_loginView addSubview:title];

    NSUserDefaults *d = [AppState preferences];
    _hostField = [self addFieldTo:_loginView label:@"Core host"
                            value:[d stringForKey:@"hostName"]
                           secure:NO y:&y width:width];
    NSString *savedPort = [d stringForKey:@"port"];
    _portField = [self addFieldTo:_loginView label:@"Port"
                            value:(savedPort.length ? savedPort : @"4242")
                           secure:NO y:&y width:width];
    _userField = [self addFieldTo:_loginView label:@"User"
                            value:[d stringForKey:@"userName"]
                           secure:NO y:&y width:width];
    _passField = (NSSecureTextField *)
                 [self addFieldTo:_loginView label:@"Password"
                            value:[d stringForKey:@"passWord"]
                           secure:YES y:&y width:width];

    _connectButton = [[NSButton alloc] initWithFrame:
                      NSMakeRect(kPad, y, 110, 28)];
    [_connectButton setTitle:@"Connect"];
    [_connectButton setBezelStyle:NSRoundedBezelStyle];
    [_connectButton setTarget:self];
    [_connectButton setAction:@selector(connectPressed:)];
    [_loginView addSubview:_connectButton];
    [self.window setDefaultButtonCell:[_connectButton cell]];
}

- (void)buildStatusView
{
    NSRect box = [_contentBox bounds];
    _statusView = [[NSView alloc] initWithFrame:box];
    [_statusView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    _statusLabel = [[NSTextField alloc] initWithFrame:
                    NSMakeRect(kPad, box.size.height / 2, box.size.width - 2 * kPad, 22)];
    [_statusLabel setBezeled:NO];
    [_statusLabel setDrawsBackground:NO];
    [_statusLabel setEditable:NO];
    [_statusLabel setSelectable:YES];
    [_statusLabel setFont:[NSFont systemFontOfSize:13]];
    [_statusLabel setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [_statusView addSubview:_statusLabel];

    _retryButton = [[NSButton alloc] initWithFrame:
                    NSMakeRect(kPad, box.size.height / 2 - 40, 110, 28)];
    [_retryButton setTitle:@"Back"];
    [_retryButton setBezelStyle:NSRoundedBezelStyle];
    [_retryButton setTarget:self];
    [_retryButton setAction:@selector(backPressed:)];
    [_retryButton setAutoresizingMask:NSViewMinYMargin];
    [_statusView addSubview:_retryButton];
}

- (void)buildChatContainer
{
    NSRect box = [_contentBox bounds];
    _chatContainer = [[NSView alloc] initWithFrame:box];
    [_chatContainer setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    NSView *chatView = [self.chat view];
    NSView *nickView = [self.nickList view];

    [chatView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [nickView setAutoresizingMask:NSViewHeightSizable | NSViewMinXMargin];

    [_chatContainer addSubview:chatView];
    [_chatContainer addSubview:nickView];

    _nickListVisible = YES;
    [self layoutChatContainer];
}

- (void)layoutChatContainer
{
    NSRect  box = [_chatContainer bounds];
    CGFloat nw  = _nickListVisible ? kNickListWidth : 0.0;

    [[self.chat view]     setFrame:NSMakeRect(0, 0, box.size.width - nw, box.size.height)];
    [[self.nickList view] setFrame:NSMakeRect(box.size.width - nw, 0, nw, box.size.height)];
    [[self.nickList view] setHidden:!_nickListVisible];
    [_chatContainer setNeedsDisplay:YES];
}

#pragma mark - State switching

- (void)showWindow:(id)sender
{
    [super showWindow:sender];
    [self resetDividers];
}

/// Put the buffer-list pane back to its nominal width.
- (void)resetDividers
{
    [_split setPosition:kSidebarWidth ofDividerAtIndex:0];
    [self layoutChatContainer];
}

- (void)showState:(QuasselUIState)state
{
    self.state = state;

    for (NSView *v in [[_contentBox subviews] copy]) {
        [v removeFromSuperview];
    }

    NSView *next = nil;
    switch (state) {
        case QuasselUIStateLogin:      next = _loginView;        break;
        case QuasselUIStateConnecting: next = _statusView;       break;
        case QuasselUIStateError:      next = _statusView;       break;
        case QuasselUIStateChat:       next = _chatContainer;    break;
    }

    [next setFrame:[_contentBox bounds]];
    [next setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [_contentBox addSubview:next];
    if (state == QuasselUIStateChat) [self layoutChatContainer];

    [_retryButton setHidden:(state != QuasselUIStateError)];
    [self.window setTitle:(state == QuasselUIStateChat) ? @"Quassel" : @"Quassel — Not connected"];
}

- (void)setStatus:(NSString *)text
{
    [_statusLabel setStringValue:text ?: @""];
}

#pragma mark - Actions

- (void)connectPressed:(id)sender
{
    NSString *host = [[_hostField stringValue]
                      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *user = [[_userField stringValue]
                      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    int port = [[_portField stringValue] intValue];

    if (host.length == 0 || user.length == 0 || port <= 0) {
        NSAlert *a = [[NSAlert alloc] init];
        [a setMessageText:@"Missing connection details"];
        [a setInformativeText:@"Enter a core host, port and user name."];
        [a runModal];
        return;
    }

    // Remembered for next launch. NOTE: no Security.framework on GNUstep, so this
    // lands in ~/Library/Preferences in the clear -- see the port plan.
    NSUserDefaults *d = [AppState preferences];
    [d setObject:host forKey:@"hostName"];
    [d setObject:[_portField stringValue] forKey:@"port"];
    [d setObject:user forKey:@"userName"];
    [d setObject:[_passField stringValue] forKey:@"passWord"];
    [d synchronize];

    [self connectWithHost:host port:port user:user password:[_passField stringValue]];
}

- (void)backPressed:(id)sender
{
    [self showState:QuasselUIStateLogin];
}

- (void)connectWithHost:(NSString *)host
                   port:(int)port
                   user:(NSString *)user
               password:(NSString *)password
{
    [self setStatus:[NSString stringWithFormat:@"Connecting to %@:%d…", host, port]];
    [self showState:QuasselUIStateConnecting];

    self.connection = [[QuasselCoreConnection alloc] init];
    self.connection.delegate = self;
    [self.bufferList setConnection:self.connection];
    [self.chat       setConnection:self.connection];
    [self.nickList   setConnection:self.connection];

    [self.connection connectTo:host port:port userName:user passWord:password];
}

- (void)disconnect
{
    [self.connection disconnect];
    self.connection = nil;
    [self.bufferList setConnection:nil];
    [self.chat setConnection:nil];
    [self.nickList setConnection:nil];
    [self showState:QuasselUIStateLogin];
}

- (void)selectBufferId:(id)bufferId
{
    [self.chat     showBufferId:bufferId];
    [self.nickList showBufferId:bufferId];
}

- (void)toggleNickList
{
    _nickListVisible = !_nickListVisible;
    [self layoutChatContainer];
}

#pragma mark - NSToolbarDelegate

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)tb
{
    return @[@"Connect", @"Disconnect", NSToolbarFlexibleSpaceItemIdentifier, @"Members"];
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)tb
{
    return @[@"Connect", @"Disconnect", NSToolbarFlexibleSpaceItemIdentifier, @"Members"];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)tb
     itemForItemIdentifier:(NSString *)ident
 willBeInsertedIntoToolbar:(BOOL)flag
{
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:ident];
    [item setLabel:ident];
    [item setTarget:self];
    if ([ident isEqualToString:@"Connect"]) {
        [item setAction:@selector(backPressed:)];
    } else if ([ident isEqualToString:@"Disconnect"]) {
        [item setAction:@selector(disconnect)];
    } else if ([ident isEqualToString:@"Members"]) {
        [item setAction:@selector(toggleNickList)];
    }
    return item;
}

#pragma mark - QuasselCoreConnectionDelegate

- (void)quasselSocketFailedConnect:(NSString *)msg
{
    [self setStatus:[NSString stringWithFormat:@"Could not connect: %@", msg]];
    [self showState:QuasselUIStateError];
}

- (void)quasselConnected      { [self setStatus:@"Connected — negotiating…"]; }
- (void)quasselEncrypted      { [self setStatus:@"Encrypted — logging in…"]; }
- (void)quasselAuthenticated  { [self setStatus:@"Authenticated — loading session…"]; }

- (void)quasselBufferListReceived
{
    [self.bufferList reload];
}

- (void)quasselNetworkInitReceived:(NSString *)networkName
{
    [self setStatus:[NSString stringWithFormat:@"Loaded %@…", networkName]];
    [self.bufferList reload];
}

- (void)quasselAllNetworkInitReceived
{
    [self.bufferList reload];
    [self.nickList reload];
}

- (void)quasselFullyConnected
{
    [self.bufferList reload];
    [self showState:QuasselUIStateChat];
}

- (void)quasselBufferListUpdated
{
    [self.bufferList reload];
    [self.nickList reload];
}

- (void)quasselSocketDidDisconnect:(NSString *)msg
{
    [self setStatus:[NSString stringWithFormat:@"Disconnected: %@",
                     msg.length ? msg : @"connection closed"]];
    [self showState:QuasselUIStateError];
}

- (void)quasselSwitchToBuffer:(BufferId *)bufferId
{
    [self.chat     showBufferId:bufferId];
    [self.nickList showBufferId:bufferId];
    [self.bufferList selectBufferId:bufferId];
}

- (void)quasselMessageReceived:(Message *)msg
                      received:(enum ReceiveStyle)style
                       onIndex:(int)i
{
    [self.chat messageReceived:msg style:style atIndex:i];
}

- (void)quasselMessagesReceived:(NSArray *)messages received:(enum ReceiveStyle)style
{
    [self.chat messagesReceived:messages style:style];
}

- (void)quasselLastSeenMsgUpdated:(MsgId *)messageId forBuffer:(BufferId *)bufferId { }

- (void)quasselNetworkNameUpdated:(NetworkId *)networkId
{
    [self.bufferList reload];
}

@end
