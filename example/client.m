#import <Foundation/Foundation.h>
#import "../include/mipc.h"
#import <unistd.h>

/**
 * Example Secure Client (Sandboxed)
 * Demonstrates reading/writing config from outside the sandbox via the server bridge.
 */

int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            printf("Usage: %s [read | write <json>]\n", argv[0]);
            return 1;
        }

        NSString *command = [NSString stringWithUTF8String:argv[1]];
        __block BOOL responseReceived = NO;

        mipc session = mipc_connect("com.aspauldingcode.libmipc.example", ^(mipc connection, const char *text) {
            (void)connection;
            printf("Example Client received: %s\n", text);
            responseReceived = YES;
        });

        if (!session) {
            fprintf(stderr, "[Client] Error: Could not connect to server.\n");
            return 1;
        }

        if ([command isEqualToString:@"read"]) {
            mipc_send(session, "get_config");
        } else if ([command isEqualToString:@"write"] && argc > 2) {
            NSString *json = [NSString stringWithUTF8String:argv[2]];
            NSString *fullCmd = [NSString stringWithFormat:@"set_config %@", json];
            mipc_send(session, [fullCmd UTF8String]);
        } else {
            printf("Invalid command or missing JSON for write.\n");
            mipc_close(session);
            return 1;
        }

        // Wait for response
        int timeout = 50; // 5 seconds
        while (!responseReceived && timeout-- > 0) {
            usleep(100000);
        }

        mipc_close(session);
    }
    return 0;
}
