#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import "mipc.h"
#import <assert.h>
#import <unistd.h>

/**
 * libmipc Discovery Tests
 * Tests the sandbox-tolerant discovery mechanism (mipc_publish / mipc_connect_dynamic).
 */

int main() {
    @autoreleasepool {
        setvbuf(stdout, NULL, _IONBF, 0);
        printf("DEBUG: Starting libmipc Discovery Tests...\n");

        NSString *testKey = [NSString stringWithFormat:@"test_discovery_%d", getpid()];
        const char *keyStr = [testKey UTF8String];
        
        // 1. Start a listener with a randomized name
        NSString *serviceName = [NSString stringWithFormat:@"com.aspauldingcode.test.%d", getpid()];
        const char *nameStr = [serviceName UTF8String];
        
        __block BOOL received = NO;
        __block NSString *receivedText = nil;
        dispatch_group_t group = dispatch_group_create();

        printf("DEBUG: Starting listener on %s\n", nameStr);
        mipc server = mipc_listen(nameStr, ^(mipc connection, const char *text) {
            receivedText = [NSString stringWithUTF8String:text];
            received = YES;
            mipc_send(connection, "ack");
            dispatch_group_leave(group);
        });
        assert(server != NULL);

        // 2. Publish the service
        printf("DEBUG: Publishing service under key %s\n", keyStr);
        bool pub_res = mipc_publish(server, keyStr);
        assert(pub_res == true);

        // 3. Connect via discovery
        printf("DEBUG: Connecting via dynamic discovery for key %s\n", keyStr);
        dispatch_group_enter(group);
        
        __block BOOL clientReceived = NO;
        mipc client = mipc_connect_dynamic(keyStr, ^(mipc connection, const char *text) {
            if (strcmp(text, "ack") == 0) {
                clientReceived = YES;
            }
        });
        assert(client != NULL);

        // 4. Send message from client to server
        printf("DEBUG: Sending message from client to server...\n");
        bool send_res = mipc_send(client, "hello discovery");
        assert(send_res == true);

        // 5. Wait for completion
        printf("DEBUG: Waiting for message delivery...\n");
        dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));

        assert(received == YES);
        assert([receivedText isEqualToString:@"hello discovery"]);
        
        // Give client a moment to receive ack
        usleep(100000); 
        assert(clientReceived == YES);

        printf("DEBUG: Cleaning up...\n");
        mipc_close(client);
        mipc_close(server);

        // Cleanup preferences
        NSString *nsKey = [NSString stringWithFormat:@"libmipc_%s", keyStr];
        CFPreferencesSetValue((__bridge CFStringRef)nsKey, NULL, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);

        printf("--- DISCOVERY TESTS PASSED ---\n");
    }
    return 0;
}
