# Fixing Sandbox Escapes for Mach IPC in libmipc

This document outlines the correct, two-step procedure for establishing Mach IPC between a sandboxed application and a privileged helper tool. This method uses a bootstrap token to connect to an intermediate "enabler" service, which then provides a process-specific token for the main service.

## 1. The Challenge: Direct Mach Lookups are Forbidden

A sandboxed application cannot directly look up a Mach port registered by a privileged process. The App Sandbox blocks this for security reasons. The solution is to use sandbox extension tokens, but the implementation requires care to be secure.

## 2. The Secure Solution: A Two-Step Token Exchange

A simple, single-token system is insecure because any process could read the token and access your service. A more robust pattern uses two tokens:

1.  **Bootstrap Token**: A general token that allows a client to connect to a limited "enabler" XPC service.
2.  **Secondary Token**: A token issued by the enabler service that is bound to a *specific client process*. This token grants access to the main, privileged XPC service.

### Workflow

1.  **Daemon Startup**: The root `launchDaemon` creates a **bootstrap token** for its enabler service (e.g., `com.company.enabler`) and writes it to a world-readable file.
2.  **Client Startup**: The sandboxed client reads and consumes the bootstrap token.
3.  **Client Connects to Enabler**: The client now has permission to make an XPC connection to the enabler service.
4.  **Client Requests Secondary Token**: The client calls an XPC method on the enabler (e.g., `getSecondaryTokenWithReply:`).
5.  **Daemon Issues Secondary Token**: The enabler service receives the request, gets the client's `audit_token_t` from the connection, and issues a **secondary token** using `sandbox_extension_issue_mach_to_process`. This binds the token to that specific client.
6.  **Client Connects to Main Service**: The client consumes the secondary token and can now securely connect to the main, privileged service (e.g., `com.company.main-service`).

## 3. Implementation Examples

### `main.m` - The Privileged `launchDaemon`

This daemon listens for two services: the public enabler and the main, protected service.

```objc
#import <Foundation/Foundation.h>
#import "sandbox_private.h"

// --- XPC Protocol & Delegate Setup --- //

@protocol DaemonSandboxProtocol
- (void)getIconServerExtensionWithReply:(void (^)(NSString *))reply;
@end

@interface DaemonDelegate : NSObject <NSXPCListenerDelegate> @end
@interface DaemonHandler : NSObject <DaemonSandboxProtocol> @end

// --- Private API for getting client audit token --- //

@interface NSXPCConnection (AuditToken)
@property (readonly) audit_token_t auditToken;
@end

// --- Implementation --- //

@implementation DaemonHandler
// This method is called by the sandboxed client.
- (void)getIconServerExtensionWithReply:(void (^)(NSString *))reply {
    NSXPCConnection *currentConn = [NSXPCConnection currentConnection];
    audit_token_t clientToken = currentConn.auditToken;

    // Issue a token for the MAIN service, but bind it to the client process.
    char *rawToken = sandbox_extension_issue_mach_to_process(
        APP_SANDBOX_MACH,
        "com.saltysoft.icon-server", // The MAIN service
        0,
        clientToken
    );

    if (rawToken) {
        NSString *nsToken = [NSString stringWithUTF8String:rawToken];
        free(rawToken);
        reply(nsToken); // Send the secondary token back to the client.
    } else {
        reply(nil);
    }
}
@end

// Issues the initial bootstrap token on daemon startup.
void IssueBootstrapToken(void) {
    // This token is for the ENABLER service.
    char *token = sandbox_extension_issue_mach(
        APP_SANDBOX_MACH,
        "com.saltysoft.icon-server-enabler", // The ENABLER service
        0
    );
    
    if (token) {
        NSString *tokenStr = [NSString stringWithUTF8String:token];
        [tokenStr writeToFile:@"/Library/Application Support/SaltySweets/enablertoken.txt"
                   atomically:YES
                     encoding:NSUTF8StringEncoding
                        error:nil];
        free(token);
    }
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        IssueBootstrapToken();
        
        // Set up and run the XPC listener for the ENABLER service.
        DaemonDelegate *delegate = [[DaemonDelegate alloc] init];
        NSXPCListener *listener = [[NSXPCListener alloc] initWithMachServiceName:@"com.saltysoft.icon-server-enabler"];
        listener.delegate = delegate;
        [listener resume];
        
        // The main service listener would also be set up here.
        
        [[NSRunLoop mainRunLoop] run];
    }
    return 0;
}
```

### `snippet.m` - The Sandboxed Client

```objc
+ (void)initXPC {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *rootTokenPath = @"/Library/Application Support/SaltySweets/enablertoken.txt";
        NSString *rootToken = [NSString stringWithContentsOfFile:rootTokenPath encoding:NSUTF8StringEncoding error:nil];
        
        if (rootToken) {
            // 1. Consume the bootstrap token.
            sandbox_extension_consume([rootToken UTF8String]);
            
            // 2. Connect to the ENABLER service.
            NSXPCConnection *daemonConn = [[NSXPCConnection alloc] initWithMachServiceName:@"com.saltysoft.icon-server-enabler" options:0];
            daemonConn.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(DaemonSandboxProtocol)];
            [daemonConn resume];
            
            id proxy = [daemonConn remoteObjectProxyWithErrorHandler:nil];
            
            // 3. Ask the enabler for a secondary, process-specific token.
            [proxy getIconServerExtensionWithReply:^(NSString *token){
                if (token) {
                    // 4. Consume the secondary token.
                    int64_t handle = sandbox_extension_consume([token UTF8String]);
                    
                    if (handle > 0) {
                        // 5. Success! Now connect to the MAIN service.
                        [self.class initXPCDirect];
                        // Remember to release the handle when done.
                        // sandbox_extension_release(handle);
                    }
                }
            }];
        }
    });
}

+ (void)initXPCDirect {
    // This function now connects to "com.saltysoft.icon-server"
    // ... (implementation is the same as in the user-provided snippet)
}
```

## 4. Private Header Details

To compile this code, you will need the following private function definitions.

```c
#import <mach/mach.h>

// Issues a token bound to a specific process via its audit token.
char *sandbox_extension_issue_mach_to_process(const char *extension_class, const char *name, uint32_t flags, audit_token_t);

// Issues a general token.
char *sandbox_extension_issue_mach(const char *extension_class, const char *name, uint32_t flags);

// Consumes a token, returning a handle.
int64_t sandbox_extension_consume(const char *extension_token);

// Releases the handle from a consumed token.
int sandbox_extension_release(int64_t extension_handle);

// Required constant for the extension class.
extern const char *APP_SANDBOX_MACH;
```

## 5. Under the Hood: `libSystem.B.dylib` and Syscalls

The `sandbox_extension_*` functions are private APIs located within `libSystem.B.dylib`, which is part of the `dyld_shared_cache`. They are not part of a standard framework.

Internally, these functions are wrappers around an even lower-level function, `__sandbox_ms`, which performs a direct **syscall** into the XNU kernel. This kernel-level interaction is what allows the sandbox to grant a temporary, specific exception to a process.

This confirms that using the `sandbox_extension_issue_*` wrapper functions is the correct and intended method. Attempting to replicate the syscall logic directly would be highly complex and prone to breaking with future OS updates. The wrappers provide the necessary abstraction.
