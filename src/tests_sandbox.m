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

static void run_sandboxed_client(const char *key) {
    printf("[Child] Entering sandbox...\n");
    
    const char *profile = 
        "(version 1)\n"
        "(allow default)\n"
        "(deny mach-lookup (global-name \"com.aspauldingcode.libmipc.test.denied\"))\n";

    char *err = NULL;
    if (sandbox_init(profile, 0, &err) != 0) {
        fprintf(stderr, "[Child] Failed to enter sandbox: %s\n", err);
        sandbox_free_error(err);
        exit(1);
    }
    printf("[Child] Sandbox applied successfully.\n");

    __block BOOL received = NO;
    mipc client = mipc_connect_dynamic(key, ^(mipc connection, const char *text) {
        (void)connection;
        if (strcmp(text, "pong") == 0) received = YES;
    });

    if (!client) {
        fprintf(stderr, "[Child] Failed to connect via dynamic discovery!\n");
        exit(1);
    }

    printf("[Child] Connected! Sending ping...\n");
    mipc_send(client, "ping");

    // Wait for pong
    for (int i = 0; i < 20 && !received; i++) usleep(100000);

    if (received) {
        printf("[Child] Received pong! Sandbox escape successful.\n");
        mipc_close(client);
        exit(0);
    } else {
        fprintf(stderr, "[Child] Timeout waiting for pong.\n");
        exit(1);
    }
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1], "--child") == 0) {
            run_sandboxed_client(argv[2]);
            return 0;
        }

        printf("DEBUG: Starting libmipc True Sandbox Verification...\n");
        
        NSString *testKey = [NSString stringWithFormat:@"sandbox_test_%d", getpid()];
        const char *keyStr = [testKey UTF8String];
        
        NSString *serviceName = [NSString stringWithFormat:@"com.aspauldingcode.libmipc.sandbox.%d", getpid()];
        
        dispatch_group_t group = dispatch_group_create();
        dispatch_group_enter(group);

        mipc server = mipc_listen([serviceName UTF8String], ^(mipc connection, const char *text) {
            (void)connection;
            printf("[Host] Received: %s\n", text);
            if (strcmp(text, "ping") == 0) {
                mipc_send(connection, "pong");
                dispatch_group_leave(group);
            }
        });
        assert(server != NULL);
        assert(mipc_publish(server, keyStr) == true);

        // Spawn sandboxed child
        char *child_argv[] = { argv[0], "--child", (char *)keyStr, NULL };
        pid_t pid;
        if (posix_spawn(&pid, argv[0], NULL, NULL, child_argv, NULL) != 0) {
            perror("posix_spawn");
            return 1;
        }

        printf("[Host] Child spawned (pid %d). Waiting for success...\n", pid);
        
        int status;
        waitpid(pid, &status, 0);
        
        BOOL success = NO;
        if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
            printf("\n--- SANDBOX VERIFICATION PASSED ---\n");
            success = YES;
        } else {
            printf("\n--- SANDBOX VERIFICATION FAILED ---\n");
        }

        mipc_close(server);
        
        // Cleanup preferences
        NSString *nsKey = [NSString stringWithFormat:@"libmipc_%s", keyStr];
        CFPreferencesSetValue((__bridge CFStringRef)nsKey, NULL, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);

        return success ? 0 : 1;
    }
}

#pragma clang diagnostic pop
