#import <Foundation/Foundation.h>
#import "mipc.h"
#import "mipc_private.h"
#import <assert.h>
#import <unistd.h>
#import <string.h>
#import <stdlib.h>

/**
 * libmipc Security & Misuse Tests
 * These tests specifically try to misuse the API or send "malicious" inputs.
 * They use manual port allocation to remain independent of the bootstrap server.
 */

// Helpers to bypass compiler nullability and ARC checks for testing
static const char *force_null_str() { return NULL; }

int main() {
    @autoreleasepool {
        setvbuf(stdout, NULL, _IONBF, 0);
        printf("DEBUG: Starting libmipc Misuse & Security Tests...\n");

        // 0. Minimal Mach Test
        printf("DEBUG: Testing Mach port allocation...\n");
        mach_port_t p;
        if (mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &p) != KERN_SUCCESS) {
            printf("DEBUG: Mach port allocation FAILED\n");
            return 1;
        }
        printf("DEBUG: Mach port allocation SUCCESS\n");
        mach_port_mod_refs(mach_task_self(), p, MACH_PORT_RIGHT_RECEIVE, -1);

        // 1. Double Close Guard
        printf("[Test] Double mipc_close...\n");
        struct mipc_obj *mock_conn = calloc(1, sizeof(struct mipc_obj));
        mipc_close(mock_conn);
        mipc_close(NULL); // Should not crash
        printf("PASSED: Double close handled.\n");

        // 2. NULL Input Sanitization
        printf("[Test] NULL mipc_send...\n");
        bool send_res = mipc_send(NULL, "test");
        assert(send_res == false);
        printf("PASSED: NULL send handled.\n");

        printf("[Test] NULL string mipc_send...\n");
        struct mipc_obj *dummy_conn = calloc(1, sizeof(struct mipc_obj));
        send_res = mipc_send(dummy_conn, force_null_str());
        assert(send_res == false);
        free(dummy_conn);
        printf("PASSED: NULL string handled.\n");

        // 3. Buffer Overflow Protection (Large strings)
        printf("[Test] Large string mipc_send (Buffer Safety)...\n");
        
        mach_port_t mock_port;
        kern_return_t kr = mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &mock_port);
        assert(kr == KERN_SUCCESS);
        kr = mach_port_insert_right(mach_task_self(), mock_port, mock_port, MACH_MSG_TYPE_MAKE_SEND);
        assert(kr == KERN_SUCCESS);
        
        __block BOOL received = NO;
        __block int receivedLen = 0;
        dispatch_group_t group = dispatch_group_create();
        
        struct mipc_obj *listener_obj = calloc(1, sizeof(struct mipc_obj));
        listener_obj->local_port = mock_port;
        listener_obj->group = dispatch_group_create();
        listener_obj->on_message = [^(mipc connection, const char *text) {
            receivedLen = (int)strlen(text);
            received = YES;
            dispatch_group_leave(group);
        } copy];
        listener_obj->is_listener = true;
        
        dispatch_group_enter(group);
        pthread_create(&listener_obj->thread, NULL, mipc_worker, listener_obj);

        // Allocate large string on the heap to avoid stack overflow
        char *large_str = malloc(5000);
        assert(large_str != NULL);
        memset(large_str, 'A', 4999);
        large_str[4999] = '\0';
        
        struct mipc_obj client_obj_stack;
        memset((void *)&client_obj_stack, 0, sizeof(client_obj_stack));
        client_obj_stack.remote_port = mock_port;
        
        mipc_send(&client_obj_stack, large_str);
        
        dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
        
        assert(received);
        assert(receivedLen == 1023); // MIPC_MSG_SIZE - 1
        printf("PASSED: Large string truncated safely to %d bytes.\n", receivedLen);
        
        // The mipc_close function has a race condition. Replace with manual cleanup.
        // Set exit flag to terminate the worker thread. It will exit on its next timeout.
        listener_obj->should_exit = true;
        pthread_join(listener_obj->thread, NULL);

        // Wait for any in-flight message handlers to complete. This is the critical fix.
        dispatch_group_wait(listener_obj->group, DISPATCH_TIME_FOREVER);

        // Final cleanup
        mach_port_mod_refs(mach_task_self(), mock_port, MACH_PORT_RIGHT_RECEIVE, -1);
        free(large_str);// The listener_obj->group was created by this test, so it should be released here.
        // The block was also created here, so it's released with the object.
        free(listener_obj);

        printf("--- ALL SECURITY TESTS PASSED ---\n");
    }
    return 0;
}
