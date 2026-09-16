//
//  QuasselSocket.m
//  Quassel for GNUstep
//

#import "QuasselSocket.h"

#if defined(GNUSTEP)
#  import <GNUstepBase/GSTLS.h>
#endif

// Declared in the GCDAsyncSocket compatibility shim. CFNetwork does not exist
// here, so the key is a plain NSString with the same name.
NSString * const kCFStreamSSLValidatesCertificateChain = @"kCFStreamSSLValidatesCertificateChain";

static NSString * const QuasselSocketErrorDomain = @"QuasselSocketErrorDomain";

@implementation QuasselSocket
{
    NSInputStream  *_in;
    NSOutputStream *_out;

    NSMutableData  *_writeQueue;     // bytes waiting for space on the output stream
    BOOL            _wantsRead;      // a readDataWithTimeout: request is outstanding
    long            _readTag;

    BOOL            _connected;
    BOOL            _didOpen;        // both streams reported NSStreamEventOpenCompleted
    BOOL            _openCountIn;
    BOOL            _openCountOut;
    BOOL            _secure;
    BOOL            _tlsRequested;
    BOOL            _closed;
    BOOL            _outScheduled;   // see _scheduleOutput:
    NSTimer        *_readPoll;      // see _startReadPoll

    NSString       *_host;
    uint16_t        _port;
}

- (instancetype)initWithDelegate:(id)aDelegate
                   delegateQueue:(dispatch_queue_t)dq
                     socketQueue:(dispatch_queue_t)sq
{
    if ((self = [super init])) {
        _delegate   = aDelegate;
        _writeQueue = [[NSMutableData alloc] init];
        _readTag    = -1;
    }
    return self;
}

- (void)dealloc
{
#ifdef QS_DEBUG
    NSLog(@"[QS] dealloc");
#endif
    [self _teardownStreams];
}

#pragma mark - Connect

- (BOOL)connectToHost:(NSString *)host
               onPort:(uint16_t)port
          withTimeout:(NSTimeInterval)timeout
                error:(NSError **)errPtr
{
    if (_in || _out) {
        if (errPtr) {
            *errPtr = [NSError errorWithDomain:QuasselSocketErrorDomain code:1
                       userInfo:@{NSLocalizedDescriptionKey: @"Socket is already connected"}];
        }
        return NO;
    }

    _host   = [host copy];
    _port   = port;
    _closed = NO;

    NSInputStream  *is = nil;
    NSOutputStream *os = nil;

    NSHost *nsHost = [NSHost hostWithName:host];
    if (nsHost == nil) {
        nsHost = [NSHost hostWithAddress:host];
    }
    if (nsHost == nil) {
        if (errPtr) {
            *errPtr = [NSError errorWithDomain:QuasselSocketErrorDomain code:2
                       userInfo:@{NSLocalizedDescriptionKey:
                                    [NSString stringWithFormat:@"Cannot resolve host %@", host]}];
        }
        return NO;
    }

    [NSStream getStreamsToHost:nsHost
                          port:(NSInteger)port
                   inputStream:&is
                  outputStream:&os];

    if (is == nil || os == nil) {
        if (errPtr) {
            *errPtr = [NSError errorWithDomain:QuasselSocketErrorDomain code:3
                       userInfo:@{NSLocalizedDescriptionKey:
                                    [NSString stringWithFormat:@"Cannot open streams to %@:%u",
                                                               host, (unsigned)port]}];
        }
        return NO;
    }

    _in  = is;
    _out = os;

    [_in  setDelegate:self];
    [_out setDelegate:self];

    [_in scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    // NOTE: the output stream is deliberately NOT left scheduled while idle.
    // GNUstep's GSInetOutputStream signals NSStreamEventHasSpaceAvailable
    // continuously whenever the socket is writable, which monopolises the run
    // loop and starves the input stream -- the symptom is that
    // NSStreamEventHasBytesAvailable never arrives and reads never happen.
    // It is scheduled on demand in -writeData: and removed again once the
    // write queue drains.
    [self _scheduleOutput:YES];

    [_in  open];
    [_out open];

    return YES;
}

- (void)disconnect
{
#ifdef QS_DEBUG
    NSLog(@"[QS] -disconnect called by engine");
#endif
    if (_closed) return;
    _closed = YES;
    [self _teardownStreams];
    _connected = NO;
    _secure    = NO;
    [self _notifyDisconnected:nil];
}

- (void)_scheduleOutput:(BOOL)wanted
{
    if (_out == nil || wanted == _outScheduled) return;
    if (wanted) {
        [_out scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    } else {
        [_out removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    }
    _outScheduled = wanted;
}

- (void)_teardownStreams
{
    [self _stopReadPoll];
    if (_in) {
        [_in setDelegate:nil];
        [_in removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [_in close];
        _in = nil;
    }
    if (_out) {
        [_out setDelegate:nil];
        if (_outScheduled) {
            [_out removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
            _outScheduled = NO;
        }
        [_out close];
        _out = nil;
    }
}

#pragma mark - State

- (BOOL)isConnected    { return _connected && !_closed; }
- (BOOL)isDisconnected { return !_connected || _closed; }
- (BOOL)isSecure       { return _secure; }

#pragma mark - IO

- (void)writeData:(NSData *)data withTimeout:(NSTimeInterval)timeout tag:(long)tag
{
    if (data.length == 0 || _closed) return;
    [_writeQueue appendData:data];
    [self _scheduleOutput:YES];
    [self _flushWriteQueue];
}

- (void)readDataWithTimeout:(NSTimeInterval)timeout tag:(long)tag
{
    _wantsRead = YES;
    _readTag   = tag;
    // Bytes may already be buffered from a previous event, so try immediately
    // rather than waiting for the next NSStreamEventHasBytesAvailable.
    [self _drainInput];
}

- (void)_flushWriteQueue
{
    if (_writeQueue.length == 0 || _out == nil) return;
    if (![_out hasSpaceAvailable]) return;   // retry on NSStreamEventHasSpaceAvailable

    NSInteger written = [_out write:(const uint8_t *)_writeQueue.bytes
                          maxLength:_writeQueue.length];
    if (written > 0) {
        [_writeQueue replaceBytesInRange:NSMakeRange(0, (NSUInteger)written)
                               withBytes:NULL length:0];
    } else if (written < 0) {
        [self _failWithStreamError:[_out streamError]];
        return;
    }

    // Drained: stop listening for writability so the input stream gets serviced.
    if (_writeQueue.length == 0) {
        [self _scheduleOutput:NO];
    }
}

- (void)_drainInput
{
    if (!_wantsRead || _in == nil) return;
    if (![_in hasBytesAvailable]) return;

    uint8_t buf[16 * 1024];
    NSInteger n = [_in read:buf maxLength:sizeof(buf)];

    if (n > 0) {
        NSData *chunk = [NSData dataWithBytes:buf length:(NSUInteger)n];
        // One-shot, matching GCDAsyncSocket: clear the request before delivering,
        // because the engine re-arms from inside its own callback.
        _wantsRead = NO;
        long tag = _readTag;

        if ([_delegate respondsToSelector:@selector(socket:didReadPartialDataOfLength:tag:)]) {
            [_delegate socket:self didReadPartialDataOfLength:(NSUInteger)n tag:tag];
        }
        if ([_delegate respondsToSelector:@selector(socket:didReadData:withTag:)]) {
            [_delegate socket:self didReadData:chunk withTag:tag];
        }
    } else if (n < 0) {
        // GNUstep's GSInetInputStream can report hasBytesAvailable and then
        // return -1 with no streamError before data has actually arrived.
        // Treat that as "nothing yet" rather than a fatal error -- failing here
        // tore the connection down immediately after ClientInit was sent.
        NSError *err = [_in streamError];
        if (err != nil) {
            [self _failWithStreamError:err];
        }
    }
}

/// GNUstep does not reliably deliver NSStreamEventHasBytesAvailable on a client
/// socket: the event can simply never arrive even with data waiting. Polling
/// readability from the run loop is the dependable path, and costs nothing while
/// idle. Verified against a live socket before adopting.
- (void)_startReadPoll
{
    if (_readPoll) return;
    _readPoll = [NSTimer scheduledTimerWithTimeInterval:0.02
                                                 target:self
                                               selector:@selector(_readPollFired:)
                                               userInfo:nil
                                                repeats:YES];
}

- (void)_stopReadPoll
{
    [_readPoll invalidate];
    _readPoll = nil;
}

- (void)_readPollFired:(NSTimer *)t
{
    if (_closed) { [self _stopReadPoll]; return; }
    [self _drainInput];
}

#pragma mark - TLS

- (void)startTLS:(NSDictionary *)tlsSettings
{
    if (_in == nil || _out == nil || _closed) return;

    _tlsRequested = YES;

    NSNumber *validates = tlsSettings[kCFStreamSSLValidatesCertificateChain];
    BOOL wantsValidation = (validates == nil) ? YES : [validates boolValue];

    // Negotiated SSL on an already-open stream pair is GNUstep's STARTTLS.
    [_in  setProperty:NSStreamSocketSecurityLevelNegotiatedSSL
               forKey:NSStreamSocketSecurityLevelKey];
    [_out setProperty:NSStreamSocketSecurityLevelNegotiatedSSL
               forKey:NSStreamSocketSecurityLevelKey];

#if defined(GNUSTEP)
    // The app connects to self-signed cores and explicitly disables chain
    // validation; without this GSTLS refuses the handshake.
    if (!wantsValidation) {
        [_in  setProperty:@"NO" forKey:GSTLSVerify];
        [_out setProperty:@"NO" forKey:GSTLSVerify];
    }
    if (_host.length) {
        [_out setProperty:_host forKey:GSTLSServerName];
    }
#endif
}

- (NSString *)debugDescription
{
    return [NSString stringWithFormat:
            @"<%@ %p host=%@:%u connected=%d secure=%d pendingWrite=%lu>",
            NSStringFromClass([self class]), self, _host, (unsigned)_port,
            (int)_connected, (int)_secure, (unsigned long)_writeQueue.length];
}

#pragma mark - performBlock

- (void)performBlock:(dispatch_block_t)block
{
    if (block) block();
}

#pragma mark - NSStreamDelegate

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)event
{
#ifdef QS_DEBUG
    static const char *names[] = {"None","OpenCompleted","HasBytesAvailable",
                                  "?","HasSpaceAvailable","?","?","?",
                                  "ErrorOccurred","?","?","?","?","?","?","?","EndEncountered"};
    NSLog(@"[QS] %s event=%lu (%s) err=%@",
          (stream == _in ? "IN " : "OUT"), (unsigned long)event,
          (event < 17 ? names[event] : "?"), [stream streamError]);
#endif
    switch (event) {

        case NSStreamEventOpenCompleted: {
            if (stream == _in)  _openCountIn  = YES;
            if (stream == _out) _openCountOut = YES;

            if (_openCountIn && _openCountOut && !_didOpen) {
                _didOpen   = YES;
                _connected = YES;
                [self _startReadPoll];
                if ([_delegate respondsToSelector:@selector(socket:didConnectToHost:port:)]) {
                    [_delegate socket:self didConnectToHost:_host port:_port];
                }
            }
            break;
        }

        case NSStreamEventHasBytesAvailable: {
            [self _checkTLSEstablished];
            [self _drainInput];
            break;
        }

        case NSStreamEventHasSpaceAvailable: {
            [self _checkTLSEstablished];
            if (_writeQueue.length > 0) {
                [self _flushWriteQueue];
            } else {
                [self _scheduleOutput:NO];
            }
            break;
        }

        case NSStreamEventErrorOccurred: {
            [self _failWithStreamError:[stream streamError]];
            break;
        }

        case NSStreamEventEndEncountered: {
            [self _failWithStreamError:nil];
            break;
        }

        default:
            break;
    }
}

/// GNUstep performs the TLS handshake inside the stream machinery; the first
/// readable/writable event after the upgrade means it succeeded.
- (void)_checkTLSEstablished
{
    if (!_tlsRequested || _secure) return;
    _secure = YES;
    if ([_delegate respondsToSelector:@selector(socketDidSecure:)]) {
        [_delegate socketDidSecure:self];
    }
}

- (void)_failWithStreamError:(NSError *)err
{
#ifdef QS_DEBUG
    NSLog(@"[QS] _failWithStreamError: %@", err);
#endif
    if (_closed) return;
    _closed    = YES;
    _connected = NO;
    _secure    = NO;
    [self _teardownStreams];
    [self _notifyDisconnected:err];
}

- (void)_notifyDisconnected:(NSError *)err
{
    if ([_delegate respondsToSelector:@selector(socketDidDisconnect:withError:)]) {
        [_delegate socketDidDisconnect:self withError:err];
    }
}

@end
