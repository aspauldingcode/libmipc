#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <notify.h>
#import "mipc.h"
#import <assert.h>
#import <unistd.h>

/**
 * libmipc Discovery & Notification Tests
 * Every detail of the sandbox-tolerant discovery is tested here.
 */

int main() {
    @autoreleasepool {
        setvbuf(stdout, NULL, _IONBF, 0);
        printf("DEBUG: Starting Comprehensive libmipc Discovery Tests...\n");

        NSString *testKey = [NSString stringWithFormat:@"test_full_%d", getpid()];
        const char *keyStr = [testKey UTF8String];
        
        // --- Test 1: Basic Connection & Messaging ---
        printf("\n[Test 1] Basic Publish & Connect...\n");
        NSString *serviceName1 = [NSString stringWithFormat:@"com.aspauldingcode.test.v1.%d", getpid()];
        
        __block BOOL received = NO;
        dispatch_group_t group = dispatch_group_create();

        mipc server1 = mipc_listen([serviceName1 UTF8String], ^(mipc connection, const char *text) {
            received = YES;
            dispatch_group_leave(group);
        });
        assert(server1 != NULL);
        assert(mipc_publish(server1, keyStr) == true);

        dispatch_group_enter(group);
        mipc client1 = mipc_connect_dynamic(keyStr, NULL);
        assert(client1 != NULL);
        assert(mipc_send(client1, "hello") == true);
        
        dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
        assert(received == YES);
        printf("PASSED: Basic connection works.\n");

        // --- Test 2: Notification Verification ---
        printf("\n[Test 2] Darwin Notification Delivery...\n");
        // The notification name is com.aspauldingcode.libmipc.update.<key>
        NSString *notifName = [NSString stringWithFormat:@"com.aspauldingcode.libmipc.update.%s", keyStr];
        int token = 0;
        uint32_t status = notify_register_check([notifName UTF8String], &token);
        assert(status == NOTIFY_STATUS_OK);

        // Publish again to trigger notification
        mipc_publish(server1, keyStr);

        int check = 0;
        status = notify_check(token, &check);
        assert(status == NOTIFY_STATUS_OK);
        assert(check != 0); // Notification was received
        printf("PASSED: Darwin notification delivered correctly.\n");
        notify_cancel(token);

        // --- Test 3: Failed Lookup ---
        printf("\n[Test 3] Non-existent Key Handling...\n");
        mipc client_fail = mipc_connect_dynamic("invalid_key_123", NULL);
        assert(client_fail == NULL);
        printf("PASSED: Invalid key handled gracefully.\n");

        // --- Test 4: Dynamic Re-publishing (Service Migration) ---
        printf("\n[Test 4] Dynamic Re-publishing (Service Migration)...\n");
        // Close old server, start new one with DIFFERENT name but SAME discovery key
        mipc_close(server1);
        
        NSString *serviceName2 = [NSString stringWithFormat:@"com.aspauldingcode.test.v2.%d", getpid()];
        __block BOOL received2 = NO;
        dispatch_group_t group2 = dispatch_group_create();

        mipc server2 = mipc_listen([serviceName2 UTF8String], ^(mipc connection, const char *text) {
            received2 = YES;
            dispatch_group_leave(group2);
        });
        assert(server2 != NULL);

        // Re-publish to the SAME key
        assert(mipc_publish(server2, keyStr) == true);

        dispatch_group_enter(group2);
        mipc client2 = mipc_connect_dynamic(keyStr, NULL);
        assert(client2 != NULL);
        assert(mipc_send(client2, "hello migration") == true);

        dispatch_group_wait(group2, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
        assert(received2 == YES);
        printf("PASSED: Migration to new service name via same key works.\n");

        // --- Test 5: Cleanup & Registry Integrity ---
        printf("\n[Test 5] Cleanup & Registry Discovery...\n");
        // Manually check the preference store
        NSString *nsKey = [NSString stringWithFormat:@"libmipc_%s", keyStr];
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPropertyListRef val = CFPreferencesCopyValue((__bridge CFStringRef)nsKey, 
                                                       kCFPreferencesAnyApplication, 
                                                       kCFPreferencesCurrentUser, 
                                                       kCFPreferencesAnyHost);
        assert(val != NULL);
        assert([(__bridge NSString *)val isEqualToString:serviceName2]);
        CFRelease(val);

        // Cleanup
        mipc_close(client1);
        mipc_close(client2);
        mipc_close(server2);

        // Final cleanup of the registry
        CFPreferencesSetValue((__bridge CFStringRef)nsKey, NULL, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);

        printf("\n--- ALL COMPREHENSIVE DISCOVERY TESTS PASSED ---\n");
    }
    return 0;
}
