//
//  ChatViewController.m
//  Quassel for GNUstep
//

#import "ChatViewController.h"
#import "MainWindowController.h"

#import "QuasselCoreConnection.h"
#import "QuasselUtils.h"
#import "Message.h"
#import "BufferInfo.h"
#import "SignedId.h"

static const CGFloat kInputH   = 26.0;
static const CGFloat kHPad     = 6.0;
static const CGFloat kVPad     = 3.0;
static const CGFloat kMinRowH  = 16.0;

@interface ChatViewController ()
{
    NSView        *_root;
    NSScrollView  *_scroll;
    NSTableView   *_table;
    NSTextField   *_input;

    NSFont        *_font;
    NSMutableArray *_rows;        // cached NSAttributedString per visible message
    CGFloat        _lastWidth;    // invalidate heights when the column resizes
}
@property (nonatomic, strong) id currentBufferId;
@end


@implementation ChatViewController

- (instancetype)initWithWindowController:(MainWindowController *)wc
{
    if ((self = [super init])) {
        _windowController = wc;
        _rows = [NSMutableArray array];
        _font = [NSFont userFixedPitchFontOfSize:11] ?: [NSFont systemFontOfSize:12];
        [self buildView];
    }
    return self;
}

- (void)buildView
{
    NSRect frame = NSMakeRect(0, 0, 760, 600);
    _root = [[NSView alloc] initWithFrame:frame];
    [_root setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    // --- input field along the bottom ---
    _input = [[NSTextField alloc] initWithFrame:
              NSMakeRect(0, 0, frame.size.width, kInputH)];
    [_input setBezeled:YES];
    [_input setEditable:YES];
    [_input setFont:[NSFont systemFontOfSize:12]];
    [_input setTarget:self];
    [_input setAction:@selector(inputSubmitted:)];
    [_input setDelegate:(id)self];
    [_input setAutoresizingMask:NSViewWidthSizable];
    [_root addSubview:_input];

    // --- chat log filling the rest ---
    NSRect tableFrame = NSMakeRect(0, kInputH + 1,
                                   frame.size.width, frame.size.height - kInputH - 1);

    _table = [[NSTableView alloc] initWithFrame:tableFrame];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"line"];
    [col setWidth:tableFrame.size.width - 4];
    [col setResizingMask:NSTableColumnAutoresizingMask];
    [_table addTableColumn:col];
    [_table setHeaderView:nil];
    [_table setDataSource:self];
    [_table setDelegate:self];
    [_table setAllowsMultipleSelection:NO];
    [_table setAllowsEmptySelection:YES];
    [_table setUsesAlternatingRowBackgroundColors:NO];
    [_table setColumnAutoresizingStyle:NSTableViewLastColumnOnlyAutoresizingStyle];

    _scroll = [[NSScrollView alloc] initWithFrame:tableFrame];
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
        [_rows removeAllObjects];
        [_table reloadData];
    }
}

#pragma mark - Buffer switching

- (void)showBufferId:(id)bufferId
{
    self.currentBufferId = bufferId;

    BufferInfo *info = [self.connection.bufferIdBufferInfoMap objectForKey:bufferId];
    [[_windowController window] setTitle:
        info ? [NSString stringWithFormat:@"Quassel — %@", info.bufferName] : @"Quassel"];

    // Ask the core for backlog the first time a buffer is opened.
    if (bufferId && ![self.connection.backlogRequestedForAlreadyBufferIdSet containsObject:bufferId]) {
        [self.connection.backlogRequestedForAlreadyBufferIdSet addObject:bufferId];
        [self.connection fetchSomeBacklog:bufferId];
    }

    [self rebuildRows];
    [self scrollToBottom];
}

- (NSArray *)currentMessages
{
    if (self.currentBufferId == nil) return @[];
    return [self.connection.bufferIdMessageListMap objectForKey:self.currentBufferId] ?: @[];
}

- (void)rebuildRows
{
    [_rows removeAllObjects];
    for (Message *m in [self currentMessages]) {
        [_rows addObject:[self attributedLineForMessage:m]];
    }
    [_table reloadData];
}

- (void)scrollToBottom
{
    NSInteger n = (NSInteger)_rows.count;
    if (n > 0) [_table scrollRowToVisible:n - 1];
}

#pragma mark - Incoming messages

- (void)messageReceived:(Message *)msg style:(enum ReceiveStyle)style atIndex:(int)index
{
    if (![[self bufferIdOfMessage:msg] isEqual:self.currentBufferId]) return;
    [self rebuildRows];
    if (style == ReceiveStyleAppended) [self scrollToBottom];
}

- (void)messagesReceived:(NSArray *)messages style:(enum ReceiveStyle)style
{
    Message *first = messages.firstObject;
    if (first && ![[self bufferIdOfMessage:first] isEqual:self.currentBufferId]) return;
    [self rebuildRows];
    if (style != ReceiveStyleBacklog) [self scrollToBottom];
}

- (id)bufferIdOfMessage:(Message *)m
{
    return [[m bufferInfo] bufferId];
}

#pragma mark - Rendering
//
// Ported from BufferViewController.m:559-661. The formatting is unchanged; only
// the colour handling differs, because QuasselUtils now returns a packed RGB
// value rather than a UIColor.

- (NSString *)plainLineForMessage:(Message *)message
{
    NSString *ts     = [QuasselUtils extractTimestamp:message];
    NSString *nick   = [QuasselUtils extractNick:message.sender];
    NSString *body   = message.contents ?: @"";

    switch (message.messageType) {
        case MessageTypeNotice:
        case MessageTypePlain:
            return [NSString stringWithFormat:@"%@ <%@> %@", ts, nick, body];
        case MessageTypeAction:
            return [NSString stringWithFormat:@"%@ * %@ %@", ts, nick, body];
        case MessageTypeJoin:
            return [NSString stringWithFormat:@"%@ --> %@", ts, message.sender];
        case MessageTypePart:
        case MessageTypeQuit:
            return [NSString stringWithFormat:@"%@ <-- %@ (%@)", ts, message.sender, body];
        case MessageTypeNick:
            return [NSString stringWithFormat:@"%@ <-> %@ is now known as %@", ts, nick, body];
        case MessageTypeDayChange:
            return @"-{ Day changed }-";
        case MessageTypeServer:
            return [NSString stringWithFormat:@"%@ * %@", ts, body];
        case MessageTypeError:
            return [NSString stringWithFormat:@"%@ Error: %@", ts, body];
        default:
            return [NSString stringWithFormat:@"%@ %@ %@", ts, nick, body];
    }
}

- (NSColor *)colorForNick:(NSString *)nick
{
    uint32_t rgb = [QuasselUtils rgbFromNick:nick];
    return [NSColor colorWithCalibratedRed:((rgb & 0xFF0000) >> 16) / 255.0
                                     green:((rgb & 0x00FF00) >>  8) / 255.0
                                      blue:( rgb & 0x0000FF)        / 255.0
                                     alpha:1.0];
}

- (NSAttributedString *)attributedLineForMessage:(Message *)message
{
    NSString *line = [self plainLineForMessage:message];

    NSMutableAttributedString *s =
        [[NSMutableAttributedString alloc] initWithString:line];
    NSRange all = NSMakeRange(0, line.length);

    [s addAttribute:NSFontAttributeName value:_font range:all];

    // Timestamps in grey.
    NSRange tsRange = [line rangeOfString:@"]"];
    if (tsRange.location != NSNotFound && [line hasPrefix:@"["]) {
        [s addAttribute:NSForegroundColorAttributeName
                  value:[NSColor grayColor]
                  range:NSMakeRange(0, tsRange.location + 1)];
    }

    // Nick in its hashed colour, matching the iOS client's palette.
    NSString *nick = [QuasselUtils extractNick:message.sender];
    if (nick.length) {
        NSRange nickRange = [line rangeOfString:nick];
        if (nickRange.location != NSNotFound) {
            [s addAttribute:NSForegroundColorAttributeName
                      value:[self colorForNick:nick]
                      range:nickRange];
        }
    }

    // Status lines are de-emphasised.
    switch (message.messageType) {
        case MessageTypeJoin:
        case MessageTypePart:
        case MessageTypeQuit:
        case MessageTypeNick:
        case MessageTypeServer:
            [s addAttribute:NSForegroundColorAttributeName
                      value:[NSColor darkGrayColor] range:all];
            break;
        case MessageTypeError:
            [s addAttribute:NSForegroundColorAttributeName
                      value:[NSColor redColor] range:all];
            break;
        default:
            break;
    }

    return s;
}

- (CGFloat)columnTextWidth
{
    CGFloat w = [[[_table tableColumns] firstObject] width];
    return MAX(40.0, w - 2 * kHPad);
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv
{
    return (NSInteger)_rows.count;
}

- (id)tableView:(NSTableView *)tv
objectValueForTableColumn:(NSTableColumn *)col
            row:(NSInteger)row
{
    if (row < 0 || row >= (NSInteger)_rows.count) return @"";
    return _rows[(NSUInteger)row];
}

#pragma mark - NSTableViewDelegate

/// The whole reason this port is native: message rows are measured individually.
- (CGFloat)tableView:(NSTableView *)tv heightOfRow:(NSInteger)row
{
    if (row < 0 || row >= (NSInteger)_rows.count) return kMinRowH;

    NSAttributedString *s = _rows[(NSUInteger)row];
    NSRect r = [s boundingRectWithSize:NSMakeSize([self columnTextWidth], 10000)
                               options:NSStringDrawingUsesLineFragmentOrigin];
    return MAX(kMinRowH, ceil(r.size.height) + 2 * kVPad);
}

- (void)tableView:(NSTableView *)tv
  willDisplayCell:(id)cell
   forTableColumn:(NSTableColumn *)col
              row:(NSInteger)row
{
    if ([cell isKindOfClass:[NSTextFieldCell class]]) {
        NSTextFieldCell *tc = (NSTextFieldCell *)cell;
        [tc setWraps:YES];
        [tc setLineBreakMode:NSLineBreakByWordWrapping];
        [tc setFont:_font];
    }
}

#pragma mark - Input

- (void)inputSubmitted:(id)sender
{
    NSString *text = [[_input stringValue]
                      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (text.length == 0 || self.currentBufferId == nil) return;

    [self.connection sendMessage:text toBuffer:self.currentBufferId];
    [_input setStringValue:@""];
    [self scrollToBottom];
}

/// Tab completion, ported from BufferViewController.m:62-107.
- (BOOL)control:(NSControl *)control
       textView:(NSTextView *)textView
doCommandBySelector:(SEL)command
{
    if (command != @selector(insertTab:)) return NO;

    NSString *text = [_input stringValue];
    NSRange lastSpace = [text rangeOfString:@" " options:NSBackwardsSearch];
    NSString *prefix  = (lastSpace.location == NSNotFound)
                        ? text
                        : [text substringFromIndex:lastSpace.location + 1];
    if (prefix.length == 0) return YES;

    BufferInfo *info = [self.connection.bufferIdBufferInfoMap
                        objectForKey:self.currentBufferId];
    if (info == nil) return YES;

    NSDictionary *users = [self.connection.networkIdUserMapMap
                           objectForKey:[info networkId]];
    NSString *match = nil;
    for (NSString *nick in users) {
        if ([[nick lowercaseString] hasPrefix:[prefix lowercaseString]]) {
            match = nick;
            break;
        }
    }
    if (match == nil) return YES;

    NSString *completed;
    if (lastSpace.location == NSNotFound) {
        completed = [NSString stringWithFormat:@"%@: ", match];
    } else {
        completed = [NSString stringWithFormat:@"%@%@ ",
                     [text substringToIndex:lastSpace.location + 1], match];
    }
    [_input setStringValue:completed];
    return YES;
}

@end
