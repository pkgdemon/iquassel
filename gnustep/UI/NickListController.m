//
//  NickListController.m
//  Quassel for GNUstep
//

#import "NickListController.h"
#import "MainWindowController.h"

#import "QuasselCoreConnection.h"
#import "QuasselUtils.h"
#import "BufferInfo.h"
#import "SignedId.h"
#import "IrcUser.h"
#import "IrcChannel.h"

@interface NickListController ()
{
    NSView       *_root;
    NSScrollView *_scroll;
    NSTableView  *_table;
    NSTextField  *_header;
    NSArray      *_nicks;          // of IrcUser
}
@property (nonatomic, strong) id currentBufferId;
@end


@implementation NickListController

- (instancetype)initWithWindowController:(MainWindowController *)wc
{
    if ((self = [super init])) {
        _windowController = wc;
        _nicks = @[];
        [self buildView];
    }
    return self;
}

- (void)buildView
{
    NSRect frame = NSMakeRect(0, 0, 160, 600);
    _root = [[NSView alloc] initWithFrame:frame];
    [_root setAutoresizingMask:NSViewHeightSizable];

    // Count header, so you can see channel size at a glance.
    CGFloat headerH = 18.0;
    _header = [[NSTextField alloc] initWithFrame:
               NSMakeRect(4, frame.size.height - headerH, frame.size.width - 8, headerH)];
    [_header setBezeled:NO];
    [_header setDrawsBackground:NO];
    [_header setEditable:NO];
    [_header setSelectable:NO];
    [_header setFont:[NSFont systemFontOfSize:10]];
    [_header setTextColor:[NSColor darkGrayColor]];
    [_header setStringValue:@""];
    [_header setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [_root addSubview:_header];

    NSRect tf = NSMakeRect(0, 0, frame.size.width, frame.size.height - headerH);
    _table = [[NSTableView alloc] initWithFrame:tf];

    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"nick"];
    [col setWidth:tf.size.width - 4];
    [col setResizingMask:NSTableColumnAutoresizingMask];
    [_table addTableColumn:col];
    [_table setHeaderView:nil];
    [_table setDataSource:self];
    [_table setDelegate:self];
    [_table setRowHeight:16.0];
    [_table setAllowsMultipleSelection:NO];
    [_table setAllowsEmptySelection:YES];
    [_table setColumnAutoresizingStyle:NSTableViewLastColumnOnlyAutoresizingStyle];
    [_table setTarget:self];
    [_table setDoubleAction:@selector(nickDoubleClicked:)];

    _scroll = [[NSScrollView alloc] initWithFrame:tf];
    [_scroll setDocumentView:_table];
    [_scroll setHasVerticalScroller:YES];
    [_scroll setHasHorizontalScroller:NO];
    [_scroll setBorderType:NSNoBorder];
    [_scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [_root addSubview:_scroll];
}

- (NSView *)view { return _root; }

- (void)setConnection:(QuasselCoreConnection *)connection
{
    _connection = connection;
    if (connection == nil) {
        self.currentBufferId = nil;
        _nicks = @[];
        [_table reloadData];
        [_header setStringValue:@""];
    }
}

#pragma mark - Model

- (void)showBufferId:(id)bufferId
{
    self.currentBufferId = bufferId;
    [self reload];
}

- (void)reload
{
    NSArray *users = @[];

    BufferInfo *info = [self.connection.bufferIdBufferInfoMap
                        objectForKey:self.currentBufferId];
    if (info != nil && info.bufferType == ChannelBuffer) {
        users = [self.connection ircUsersForChannelWithBufferId:self.currentBufferId] ?: @[];
    }

    // Case-insensitive by nick, the way every other IRC client orders it.
    _nicks = [users sortedArrayUsingComparator:^NSComparisonResult(IrcUser *a, IrcUser *b) {
        return [(a.nick ?: @"") caseInsensitiveCompare:(b.nick ?: @"")];
    }];

    [_header setStringValue:(_nicks.count
        ? [NSString stringWithFormat:@"%lu %@",
           (unsigned long)_nicks.count, (_nicks.count == 1 ? @"member" : @"members")]
        : @"")];

    [_table reloadData];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv
{
    return (NSInteger)_nicks.count;
}

- (id)tableView:(NSTableView *)tv
objectValueForTableColumn:(NSTableColumn *)col
            row:(NSInteger)row
{
    if (row < 0 || row >= (NSInteger)_nicks.count) return @"";

    IrcUser *u = _nicks[(NSUInteger)row];
    NSString *nick = u.nick ?: @"";

    NSMutableAttributedString *s =
        [[NSMutableAttributedString alloc] initWithString:nick];
    NSRange all = NSMakeRange(0, nick.length);

    [s addAttribute:NSFontAttributeName
              value:[NSFont systemFontOfSize:11] range:all];

    // Same hashed palette the chat log uses, so a nick is the same colour in
    // both places.
    uint32_t rgb = [QuasselUtils rgbFromNick:nick];
    NSColor *c = [NSColor colorWithCalibratedRed:((rgb & 0xFF0000) >> 16) / 255.0
                                           green:((rgb & 0x00FF00) >>  8) / 255.0
                                            blue:( rgb & 0x0000FF)        / 255.0
                                           alpha:1.0];
    [s addAttribute:NSForegroundColorAttributeName value:c range:all];

    if (u.away) {
        [s addAttribute:NSForegroundColorAttributeName
                  value:[NSColor grayColor] range:all];
        [s addAttribute:NSObliquenessAttributeName value:@(0.15) range:all];
    }

    return s;
}

#pragma mark - Actions

/// Double-click opens (or switches to) a query with that user, matching the
/// iOS client's tap behaviour.
- (void)nickDoubleClicked:(id)sender
{
    NSInteger row = [_table clickedRow];
    if (row < 0) row = [_table selectedRow];
    if (row < 0 || row >= (NSInteger)_nicks.count) return;

    IrcUser *u = _nicks[(NSUInteger)row];
    BufferInfo *info = [self.connection.bufferIdBufferInfoMap
                        objectForKey:self.currentBufferId];
    if (info == nil) return;

    [self.connection openQueryBufferForUser:u onNetwork:[info networkId]];
}

@end
