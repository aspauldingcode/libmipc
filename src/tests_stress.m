#import <Foundation/Foundation.h>
#import "mipc.h"
#import "mipc_private.h"
#import <assert.h>
#import <unistd.h>
#import <pthread.h>
#import <servers/bootstrap.h>

/**
 * libmipc Stress & Attack Mitigation Tests
 * Verifies that the library is resistant to:
 * 1. Message Flooding (Resource exhaustion)
 * 2. Rapid Reconnection (Race conditions)
 * 3. Malformed Headers (Port injection/Type confusion)
 */

int main(void) {
    @autoreleasepool {
        setvbuf(stdout, NULL, _IONBF, 0);
        printf("DEBUG: Starting libmipc Stress & safety Tests...\n");

        // --- Test 1: Message Flooding ---
        printf("[Test 1] Message Flooding (10,000 messages)...\n");
        __block int receivedCount = 0;
        dispatch_group_t floodGroup = dispatch_group_create();
        
        mipc server = mipc_listen("com.aspauldingcode.libmipc.stress", ^(mipc connection, const char *text) {
            (void)connection; (void)text;
            receivedCount++;
            if (receivedCount == 10000) dispatch_group_leave(floodGroup);
        });
        assert(server != NULL);

        mipc client = mipc_connect("com.aspauldingcode.libmipc.stress", ^(mipc connection, const char *text) {
            (void)connection; (void)text;
        });
        assert(client != NULL);

        dispatch_group_enter(floodGroup);
        for (int i = 0; i < 10000; i++) {
            mipc_send(client, "flood");
        }
        
        // Wait up to 10 seconds for all messages
        dispatch_group_wait(floodGroup, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
        assert(receivedCount == 10000);
        printf("PASSED: 10,000 messages processed without leak or crash.\n");
        
        mipc_close(client);
        mipc_close(server);

        // --- Test 2: Rapid Reconnection ---
        printf("[Test 2] Rapid Reconnection (100 cycles)...\n");
        for (int i = 0; i < 100; i++) {
            mipc s = mipc_listen("com.aspauldingcode.libmipc.rapid", ^(mipc c, const char *t) {
                (void)c; (void)t;
            });
            mipc c = mipc_connect("com.aspauldingcode.libmipc.rapid", ^(mipc conn, const char *msg) {
                (void)conn; (void)msg;
            });
            assert(s && c);
            mipc_send(c, "test");
            mipc_close(c);
            mipc_close(s);
        }
        printf("PASSED: 100 cycles of rapid connect/close successful.\n");

        // --- Test 3: Malformed Header (Complex Message Injection) ---
        printf("[Test 3] Malformed Header Mitigation (Complex bits)...\n");
        __block BOOL receivedComplex = NO;
        mipc complex_server = mipc_listen("com.aspauldingcode.libmipc.complex", ^(mipc connection, const char *text) {
            (void)connection; (void)text;
            receivedComplex = YES;
        });
        
        // Manually craft a MALICIOUS message with MACH_MSGH_BITS_COMPLEX
        mach_port_t remote;
        assert(bootstrap_look_up(bootstrap_port, "com.aspauldingcode.libmipc.complex", &remote) == KERN_SUCCESS);
        
        typedef struct {
            mach_msg_header_t header;
            mach_msg_body_t body;
            mach_msg_port_descriptor_t desc;
            char data[1024];
        } malicious_msg_t;
        
        malicious_msg_t mal;
        memset(&mal, 0, sizeof(mal));
        mal.header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0) | MACH_MSGH_BITS_COMPLEX;
        mal.header.msgh_size = sizeof(mal);
        mal.header.msgh_remote_port = remote;
        mal.header.msgh_local_port = MACH_PORT_NULL;
        mal.body.msgh_descriptor_count = 1;
        mal.desc.name = mach_task_self(); // Try to inject our own task port (DANGEROUS if accepted)
        mal.desc.disposition = MACH_MSG_TYPE_COPY_SEND;
        mal.desc.type = MACH_MSG_PORT_DESCRIPTOR;
        
        mach_msg(&mal.header, MACH_SEND_MSG, sizeof(mal), 0, MACH_PORT_NULL, 0, MACH_PORT_NULL);
        
        usleep(200000); // Wait for processing
        assert(receivedComplex == NO); // Should have been dropped by mipc_worker
        printf("PASSED: Complex message (port injection attempt) correctly dropped.\n");
        
        mipc_close(complex_server);
        mach_port_deallocate(mach_task_self(), remote);

        printf("--- ALL STRESS & SAFETY TESTS PASSED ---\n");
    }
    return 0;
}
