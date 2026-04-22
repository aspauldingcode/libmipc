#import <Foundation/Foundation.h>

// Forward-declare the private sandbox functions
#include "sandbox_private.h"

// This daemon will handle two responsibilities:
// 1. Act as an "enabler" service that hands out process-specific tokens.
// 2. Host the actual main service that clients will connect to.

// +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// MARK: - XPC Protocols
// +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

/**
 * The protocol for our "enabler" service. Sandboxed clients will call this
 * to get a token for the main service.
 */
@protocol MIPCEnablerProtocol
- (void)getMIPCServiceExtensionWithReply:(void (^)(NSString *))reply;
@end

/**
 * The protocol for the main, protected service.
 * This is where the actual IPC logic for your application would go.
 */
@protocol MIPCMainServiceProtocol
- (void)performAction:(NSString *)action withReply:(void (^)(NSString *))reply;
@end

// +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// MARK: - XPC Delegate & Handlers
// +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

@interface MIPCDelegate : NSObject <NSXPCListenerDelegate> @end
@interface MIPCEnablerHandler : NSObject <MIPCEnablerProtocol> @end
@interface MIPCMainServiceHandler : NSObject <MIPCMainServiceProtocol> @end

// Private API to get the audit token from an XPC connection
@interface NSXPCConnection (AuditToken)
@property (readonly) audit_token_t auditToken;
@end

@implementation MIPCDelegate
- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection {
    // This delegate is for the enabler service
    newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(MIPCEnablerProtocol)];
    newConnection.exportedObject = [[MIPCEnablerHandler alloc] init];
    [newConnection resume];
    return YES;
}
@end

@interface MIPCMainServiceDelegate : NSObject <NSXPCListenerDelegate> @end
@implementation MIPCMainServiceDelegate
- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection {
    // This delegate is for the main service
    newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(MIPCMainServiceProtocol)];
    newConnection.exportedObject = [[MIPCMainServiceHandler alloc] init];
    [newConnection resume];
    return YES;
}
@end

@implementation MIPCEnablerHandler
- (void)getMIPCServiceExtensionWithReply:(void (^)(NSString *))reply {
    NSXPCConnection *currentConn = [NSXPCConnection currentConnection];
    audit_token_t clientToken = currentConn.auditToken;

    // Issue a token for the MAIN service, bound to the client's process.
    char *rawToken = sandbox_extension_issue_mach_to_process(
        APP_SANDBOX_MACH,
        "com.libmipc.main-service", // The main, protected service
        0,
        clientToken
    );

    if (rawToken) {
        NSString *nsToken = [NSString stringWithUTF8String:rawToken];
        free(rawToken);
        reply(nsToken); // Send the secondary token back to the client.
    } else {
        NSLog(@"[mipcd] Failed to issue secondary token.");
        reply(nil);
    }
}
@end

@implementation MIPCMainServiceHandler
- (void)performAction:(NSString *)action withReply:(void (^)(NSString *))reply {
    NSLog(@"[mipcd] Main service received action: %@", action);
    reply([NSString stringWithFormat:@"Acknowledged: %@", action]);
}
@end

// +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// MARK: - Bootstrap Token Logic
// +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

void IssueBootstrapToken(void) {
    // This token is for the ENABLER service.
    char *token = sandbox_extension_issue_mach(
        APP_SANDBOX_MACH,
        "com.libmipc.enabler", // The public-facing enabler service
        0
    );
    
    if (token) {
        // Store the token in a location readable by sandboxed apps.
        // A group container is ideal, but for a general library, 
        // /tmp is a reasonable, stateless default.
        NSString *tokenPath = @"/tmp/libmipc_enabler_token.txt";
        NSString *tokenStr = [NSString stringWithUTF8String:token];
        [tokenStr writeToFile:tokenPath
                   atomically:YES
                     encoding:NSUTF8StringEncoding
                        error:nil];
        free(token);
    }
}

// +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// MARK: - Main Entry Point
// +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

int main(__unused int argc, __unused const char * argv[]) {
    @autoreleasepool {
        // 1. Issue the bootstrap token for clients to find the enabler service.
        IssueBootstrapToken();
        
        // 2. Set up and run the XPC listener for the ENABLER service.
        MIPCDelegate *enablerDelegate = [[MIPCDelegate alloc] init];
        NSXPCListener *enablerListener = [[NSXPCListener alloc] initWithMachServiceName:@"com.libmipc.enabler"];
        enablerListener.delegate = enablerDelegate;
        [enablerListener resume];

        // 3. Set up and run the XPC listener for the MAIN service.
        MIPCMainServiceDelegate *mainServiceDelegate = [[MIPCMainServiceDelegate alloc] init];
        NSXPCListener *mainServiceListener = [[NSXPCListener alloc] initWithMachServiceName:@"com.libmipc.main-service"];
        mainServiceListener.delegate = mainServiceDelegate;
        [mainServiceListener resume];
        
        NSLog(@"[mipcd] Daemon started. Listening for enabler and main service connections.");
        [[NSRunLoop mainRunLoop] run];
    }
    return 0;
}
