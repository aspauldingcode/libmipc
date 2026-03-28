#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <servers/bootstrap.h>
#import <pthread.h>
#import <notify.h>
#import <CoreFoundation/CoreFoundation.h>
#import "mipc.h"
#import "mipc_private.h"

#include <string.h>

#define MIPC_MSG_SIZE 65536

void *mipc_worker(void *arg) {
    mipc bus = (mipc)arg;
    mipc_rcv_msg_t msg;
    kern_return_t kr;

    while (!bus->should_exit) {
        memset(&msg, 0, sizeof(msg));
        kr = mach_msg(&msg.msg.header,
                      MACH_RCV_MSG | MACH_RCV_INTERRUPT | MACH_RCV_TIMEOUT,
                      0,
                      sizeof(msg),
                      bus->local_port,
                      100, // 100ms timeout
                      MACH_PORT_NULL);

        if (kr == KERN_SUCCESS) {
            // Ignore empty wake-up messages
            if (msg.msg.header.msgh_size <= sizeof(mach_msg_header_t)) {
                continue;
            }
            // Security: Explicitly null-terminate the received data
            msg.msg.data[MIPC_MSG_SIZE - 1] = '\0';
            
            if (bus->on_message) {
                struct mipc_obj *connection = calloc(1, sizeof(struct mipc_obj));
                if (connection) {
                    connection->remote_port = msg.msg.header.msgh_remote_port;
                    connection->local_port = bus->local_port; 
                    
                    char *data_copy = strdup(msg.msg.data);
                    if (data_copy) {
                        dispatch_group_enter(bus->group);
                        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                            bus->on_message(connection, data_copy);
                            free(data_copy);
                            // free(connection); // REMOVED: User (helper) now owns this connection
                            dispatch_group_leave(bus->group);
                        });
                    } else {
                        free(connection);
                    }
                }
            }
        } else if (kr == MACH_RCV_PORT_DIED || kr == MACH_RCV_INVALID_NAME || kr == MACH_RCV_PORT_CHANGED) {
            break;
        }
    }
    return NULL;
}

mipc _Nullable mipc_listen(const char *name, void (^on_message)(mipc connection, const char *text)) {
    if (!name || !on_message) return NULL;
    
    mach_port_t port;
    kern_return_t kr = bootstrap_check_in(bootstrap_port, name, &port);
    if (kr != KERN_SUCCESS) return NULL;

    mipc bus = calloc(1, sizeof(struct mipc_obj));
    if (!bus) return NULL;
    
    bus->name = strdup(name);
    bus->local_port = port;
    bus->is_listener = true;
    bus->on_message = [on_message copy];
    bus->group = dispatch_group_create();
    
    if (pthread_create(&bus->thread, NULL, mipc_worker, bus) != 0) {
        mach_port_mod_refs(mach_task_self(), port, MACH_PORT_RIGHT_RECEIVE, -1);
        free(bus);
        return NULL;
    }
    return bus;
}

mipc _Nullable mipc_connect(const char *name, void (^on_message)(mipc connection, const char *text)) {
    if (!name) return NULL;
    
    mach_port_t remote_port;
    kern_return_t kr = bootstrap_look_up(bootstrap_port, name, &remote_port);
    if (kr != KERN_SUCCESS) return NULL;

    mipc bus = calloc(1, sizeof(struct mipc_obj));
    if (!bus) {
        mach_port_deallocate(mach_task_self(), remote_port);
        return NULL;
    }
    
    bus->name = NULL;
    bus->remote_port = remote_port;
    bus->on_message = [on_message copy];
    bus->group = dispatch_group_create();

    kr = mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &bus->local_port);
    if (kr == KERN_SUCCESS) {
        mach_port_insert_right(mach_task_self(), bus->local_port, bus->local_port, MACH_MSG_TYPE_MAKE_SEND);
    }

    if (on_message && bus->local_port != MACH_PORT_NULL) {
        if (pthread_create(&bus->thread, NULL, mipc_worker, bus) != 0) {
            mipc_close(bus);
            return NULL;
        }
    }

    return bus;
}

bool mipc_send(mipc _Nullable connection, const char *text_str) {
    if (!connection || !text_str || connection->remote_port == MACH_PORT_NULL) return false;

    mipc_raw_msg_t msg;
    memset(&msg, 0, sizeof(msg));
    
    msg.header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 
                                         (connection->local_port != MACH_PORT_NULL ? MACH_MSG_TYPE_MAKE_SEND : 0));
    msg.header.msgh_remote_port = connection->remote_port;
    msg.header.msgh_local_port = connection->local_port;
    msg.header.msgh_size = sizeof(msg);
    
    // Security: Controlled copy with guaranteed null termination
    strncpy(msg.data, text_str, MIPC_MSG_SIZE - 1);
    msg.data[MIPC_MSG_SIZE - 1] = '\0';

    kern_return_t kr = mach_msg(&msg.header,
                                 MACH_SEND_MSG,
                                 sizeof(msg),
                                 0,
                                 MACH_PORT_NULL,
                                 MACH_MSG_TIMEOUT_NONE,
                                 MACH_PORT_NULL);
    
    return kr == KERN_SUCCESS;
}

bool mipc_publish(mipc connection, const char *key) {
    if (!connection || !key || !connection->name || !connection->is_listener) return false;

    NSString *nsKey = [NSString stringWithFormat:@"libmipc_%s", key];
    NSString *nsValue = [NSString stringWithUTF8String:connection->name];

    CFPreferencesSetValue((__bridge CFStringRef)nsKey,
                          (__bridge CFStringRef)nsValue,
                          kCFPreferencesAnyApplication,
                          kCFPreferencesCurrentUser,
                          kCFPreferencesAnyHost);
    
    CFPreferencesSynchronize(kCFPreferencesAnyApplication,
                             kCFPreferencesCurrentUser,
                             kCFPreferencesAnyHost);

    // Also post a notification to alert clients
    NSString *notifName = [NSString stringWithFormat:@"com.aspauldingcode.libmipc.update.%s", key];
    notify_post([notifName UTF8String]);

    return true;
}

mipc _Nullable mipc_connect_dynamic(const char *key, void (^on_message)(mipc connection, const char *text)) {
    if (!key) return NULL;

    NSString *nsKey = [NSString stringWithFormat:@"libmipc_%s", key];
    
    // Force a sync to get the latest from other processes
    CFPreferencesSynchronize(kCFPreferencesAnyApplication,
                             kCFPreferencesCurrentUser,
                             kCFPreferencesAnyHost);

    CFPropertyListRef val = CFPreferencesCopyValue((__bridge CFStringRef)nsKey,
                                                   kCFPreferencesAnyApplication,
                                                   kCFPreferencesCurrentUser,
                                                   kCFPreferencesAnyHost);
    
    if (!val || CFGetTypeID(val) != CFStringGetTypeID()) {
        if (val) CFRelease(val);
        return NULL;
    }

    NSString *serviceName = (__bridge NSString *)val;
    mipc conn = mipc_connect([serviceName UTF8String], on_message);
    
    CFRelease(val);
    return conn;
}

void mipc_close(mipc _Nullable connection) {
    if (!connection || connection->should_exit) return;
    
    connection->should_exit = true;
    
    // For listeners, send a poison pill to unblock the worker thread
    if (connection->is_listener && connection->local_port != MACH_PORT_NULL) {
        mipc_raw_msg_t msg;
        memset(&msg, 0, sizeof(msg));
        msg.header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
        msg.header.msgh_remote_port = connection->local_port;
        msg.header.msgh_local_port = MACH_PORT_NULL;
        msg.header.msgh_size = sizeof(msg) - MIPC_MSG_SIZE; // Empty message
        mach_msg(&msg.header, MACH_SEND_MSG, msg.header.msgh_size, 0, MACH_PORT_NULL, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
    }
    
    // Join worker thread
    if (connection->thread != 0) {
        pthread_join(connection->thread, NULL);
        connection->thread = 0;
    }
    
    // Deallocate local receive right
    if (connection->local_port != MACH_PORT_NULL) {
        // Stop the worker thread by destroying its port
        mach_port_mod_refs(mach_task_self(), connection->local_port, MACH_PORT_RIGHT_RECEIVE, -1);
        connection->local_port = MACH_PORT_NULL;
    }

    if (connection->remote_port != MACH_PORT_NULL) {
        mach_port_deallocate(mach_task_self(), connection->remote_port);
        connection->remote_port = MACH_PORT_NULL;
    }
    
    // Wait for all in-flight message blocks to complete
    if (connection->group) {
        dispatch_group_wait(connection->group, DISPATCH_TIME_FOREVER);
    }

    free(connection->name);
    free(connection);
}
