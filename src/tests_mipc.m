#import <Foundation/Foundation.h>
#import "mipc.h"
#import "mipc_private.h"
#import <assert.h>
#import <unistd.h>
#import <string.h>

int main() {
    @autoreleasepool {
        __block NSString *serverMsg = nil;
        dispatch_group_t server_group = dispatch_group_create();
        
        mach_port_t mock_port;
        kern_return_t kr = mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &mock_port);
        assert(kr == KERN_SUCCESS);
        kr = mach_port_insert_right(mach_task_self(), mock_port, mock_port, MACH_MSG_TYPE_MAKE_SEND);
        assert(kr == KERN_SUCCESS);

        struct mipc_obj *listener_obj = calloc(1, sizeof(struct mipc_obj));
        listener_obj->local_port = mock_port;
        listener_obj->group = dispatch_group_create();
        listener_obj->on_message = [^(mipc connection, const char *text) {
            serverMsg = [NSString stringWithUTF8String:text];
            printf("Mock Listener received: %s\n", text);
            
            // Reply back (manually for the test)
            mipc_send(connection, "ACK from Server");
            dispatch_group_leave(server_group);
        } copy];
        listener_obj->is_listener = true;
        pthread_create(&listener_obj->thread, NULL, mipc_worker, listener_obj);
        
        usleep(100000);
        
        __block NSString *clientMsg = nil;
        dispatch_group_t client_group = dispatch_group_create();
        
        struct mipc_obj *client_obj = calloc(1, sizeof(struct mipc_obj));
        client_obj->local_port = MACH_PORT_NULL; // Client doesn't have a listener port here
        client_obj->remote_port = mock_port;
        client_obj->group = dispatch_group_create();
        client_obj->on_message = [^(mipc connection, const char *text) {
            clientMsg = [NSString stringWithUTF8String:text];
            printf("Client received: %s\n", text);
            dispatch_group_leave(client_group);
        } copy];
        
        // Manual client-side listener thread for the reply
        mach_port_t client_rcv_port;
        kr = mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &client_rcv_port);
        assert(kr == KERN_SUCCESS);
        client_obj->local_port = client_rcv_port;
        dispatch_group_enter(client_group);
        pthread_create(&client_obj->thread, NULL, mipc_worker, client_obj);

        printf("Client sending message...\n");
        dispatch_group_enter(server_group);
        mipc_send(client_obj, "Hello Server");
        
        // Wait for server to receive
        dispatch_group_wait(server_group, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
        assert([serverMsg isEqualToString:@"Hello Server"]);
        
        // Wait for client to receive reply
        dispatch_group_wait(client_group, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
        assert([clientMsg isEqualToString:@"ACK from Server"]);
        
        // Cleanup
        listener_obj->should_exit = true;
        client_obj->should_exit = true;
        
        pthread_join(listener_obj->thread, NULL);
        pthread_join(client_obj->thread, NULL);
        
        mach_port_mod_refs(mach_task_self(), mock_port, MACH_PORT_RIGHT_RECEIVE, -1);
        mach_port_mod_refs(mach_task_self(), client_rcv_port, MACH_PORT_RIGHT_RECEIVE, -1);
        
        free(listener_obj);
        free(client_obj);
        
        printf("MIPC Bootstrap-Independent API Test PASSED\n");
    }
    return 0;
}
