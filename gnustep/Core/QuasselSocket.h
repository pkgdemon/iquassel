//
//  QuasselSocket.h
//  Quassel for GNUstep
//
//  Drop-in replacement for the twelve-selector subset of GCDAsyncSocket that
//  QuasselCoreConnection actually uses, implemented on NSStream.
//
//  Why this exists: CocoaAsyncSocket's TLS path is SecureTransport
//  (SSLCreateContext / SSLHandshake / SecTrust...), and GNUstep has no
//  Security.framework at all. Rather than port 7,430 lines, this implements the
//  small surface the app needs on top of NSStream, whose GNUstep implementation
//  already carries a GnuTLS handler (see GSSocketStream.m / GSTLS.m).
//
//  STARTTLS after connect -- required by the Quassel handshake, which upgrades
//  only once ClientInitAck has been received -- maps onto setting
//  NSStreamSocketSecurityLevelKey on an already-open stream pair.
//

#import <Foundation/Foundation.h>

@class QuasselSocket;

@protocol QuasselSocketDelegate <NSObject>
@optional
- (void)socket:(QuasselSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port;
- (void)socket:(QuasselSocket *)sock didReadData:(NSData *)data withTag:(long)tag;
- (void)socket:(QuasselSocket *)sock didReadPartialDataOfLength:(NSUInteger)partialLength tag:(long)tag;
- (void)socketDidSecure:(QuasselSocket *)sock;
- (void)socketDidDisconnect:(QuasselSocket *)sock withError:(NSError *)err;
@end


@interface QuasselSocket : NSObject <NSStreamDelegate>

@property (nonatomic, weak) id delegate;   // id, not id<...>: the engine does not formally adopt the protocol

/// dq/sq are accepted for source compatibility with GCDAsyncSocket and ignored:
/// NSStream is driven by the run loop, and the engine already marshals onto the
/// main thread itself.
- (instancetype)initWithDelegate:(id)aDelegate
                   delegateQueue:(dispatch_queue_t)dq
                     socketQueue:(dispatch_queue_t)sq;

- (BOOL)connectToHost:(NSString *)host
               onPort:(uint16_t)port
          withTimeout:(NSTimeInterval)timeout
                error:(NSError **)errPtr;

- (void)disconnect;

@property (nonatomic, readonly) BOOL isConnected;
@property (nonatomic, readonly) BOOL isDisconnected;
@property (nonatomic, readonly) BOOL isSecure;

- (void)writeData:(NSData *)data withTimeout:(NSTimeInterval)timeout tag:(long)tag;

/// One-shot read request, matching GCDAsyncSocket semantics: with timeout -1 and
/// tag -1 the engine is asking for "whatever arrives next". Delivered via
/// -socket:didReadData:withTag:, after which the engine asks again.
- (void)readDataWithTimeout:(NSTimeInterval)timeout tag:(long)tag;

/// Upgrade an open connection to TLS. Honours kCFStreamSSLValidatesCertificateChain
/// = NO, which is what the app passes.
- (void)startTLS:(NSDictionary *)tlsSettings;

/// GNUstep's NSObject has no -debugDescription; the engine logs with it.
- (NSString *)debugDescription;

/// GCDAsyncSocket ran this on its internal socket queue; here the work is already
/// on the run-loop thread, so the block is simply executed.
- (void)performBlock:(dispatch_block_t)block;

@end
