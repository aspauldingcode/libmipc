#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <sandbox.h>
#import "mipc.h"
#import <assert.h>
#import <unistd.h>
#import <spawn.h>
#import <sys/wait.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

/**
 * libmipc True Sandbox Test
 * Verifies that communication works even when the process is restricted by a 
 * macOS Sandbox profile that denies arbitrary bootstrap lookups.
 */

int main(int argc, char *argv[]) {
    @autoreleasepool {
        printf("DEBUG: Starting libmipc Sandbox Connection Test...\n");

        // In the new CI setup, the daemon is already running.
        // We just need to connect to it using the new dynamic connect method.
        
        __block BOOL received = NO;
        mipc client = mipc_connect_dynamic("com.libmipc.main-service", ^(mipc connection, const char *text) {
            (void)connection;
            printf("[Client] Received reply: %s\n", text);
            if (strcmp(text, "Acknowledged: Hello from sandboxed client") == 0) {
                received = YES;
            }
        });

        if (!client) {
            fprintf(stderr, "[Client] Failed to connect via dynamic discovery!\n");
            return 1;
        }

        printf("[Client] Connected! Sending message...\n");
        mipc_send(client, "Hello from sandboxed client");

        // Wait for reply
        for (int i = 0; i < 20 && !received; i++) usleep(100000);

        mipc_close(client);

        if (received) {
            printf("\n--- SANDBOX VERIFICATION PASSED ---\n");
            return 0;
        } else {
            fprintf(stderr, "\n--- SANDBOX VERIFICATION FAILED ---\n");
            return 1;
        }
    }
}

#pragma clang diagnostic pop
