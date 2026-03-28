#import <notify.h>
#import <CoreFoundation/CoreFoundation.h>
#import <pthread.h>
#import <servers/bootstrap.h>
#import "mipc.h"
#import "mipc_private.h"

#include <string.h>

#define MIPC_MSG_SIZE 65536

void *mipc_worker(void *arg) {
    mipc bus = (mipc)arg;
    mipc_rcv_msg_t msg;
    while (!bus->should_exit) {
        kern_return_t kr = mach_msg(&msg.msg.header,
                      MACH_RCV_MSG | MACH_RCV_INTERRUPT | MACH_RCV_TIMEOUT,
                      0, sizeof(msg), bus->local_port, 100, MACH_PORT_NULL);

        if (kr == KERN_SUCCESS) {
            if ((msg.msg.header.msgh_bits & MACH_MSGH_BITS_COMPLEX) || 
                msg.msg.header.msgh_size <= sizeof(mach_msg_header_t)) continue;
            
            msg.msg.data[MIPC_MSG_SIZE - 1] = '\0';
            pthread_mutex_lock(&bus->lock);
            void (^handler)(mipc, const char *) = [bus->on_message copy];
            pthread_mutex_unlock(&bus->lock);

            if (handler) {
                struct mipc_obj *conn = calloc(1, sizeof(struct mipc_obj));
                if (conn) {
                    conn->remote_port = msg.msg.header.msgh_remote_port;
                    conn->local_port = bus->local_port; 
                    pthread_mutex_init(&conn->lock, NULL);
                    char *data = strdup(msg.msg.data);
                    dispatch_group_enter(bus->group);
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                        handler(conn, data);
                        free(data);
                        pthread_mutex_destroy(&conn->lock);
                        free(conn);
                        dispatch_group_leave(bus->group);
                    });
                }
            }
        } else if (kr != MACH_RCV_TIMED_OUT && kr != MACH_RCV_INTERRUPTED) break;
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
    
    // Increase queue limit for high-frequency listeners
    mach_port_limits_t limits = { .mpl_qlimit = MACH_PORT_QLIMIT_MAX };
    mach_port_set_attributes(mach_task_self(), port, MACH_PORT_LIMITS_INFO, (mach_port_info_t)&limits, MACH_PORT_LIMITS_INFO_COUNT);

    bus->name = strdup(name);
    bus->local_port = port;
    bus->is_listener = true;
    bus->on_message = [on_message copy];
    bus->group = dispatch_group_create();
    pthread_mutex_init(&bus->lock, NULL);
    
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
    pthread_mutex_init(&bus->lock, NULL);

    kr = mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &bus->local_port);
    if (kr == KERN_SUCCESS) {
        mach_port_limits_t limits = { .mpl_qlimit = MACH_PORT_QLIMIT_MAX };
        mach_port_set_attributes(mach_task_self(), bus->local_port, MACH_PORT_LIMITS_INFO, (mach_port_info_t)&limits, MACH_PORT_LIMITS_INFO_COUNT);
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
    if (!connection || !text_str) return false;

    pthread_mutex_lock(&connection->lock);
    mach_port_t remote = connection->remote_port;
    mach_port_t local = connection->local_port;
    pthread_mutex_unlock(&connection->lock);

    if (remote == MACH_PORT_NULL) return false;

    mipc_raw_msg_t msg;
    memset(&msg, 0, sizeof(msg));
    
    // Security: Only attach local port if we actually have one
    mach_msg_type_name_t local_type = (local != MACH_PORT_NULL) ? MACH_MSG_TYPE_MAKE_SEND : 0;
    msg.header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, local_type);
    msg.header.msgh_size = sizeof(msg);
    msg.header.msgh_remote_port = remote;
    msg.header.msgh_local_port = local;
    msg.header.msgh_id = 1;
    
    strncpy(msg.data, text_str, MIPC_MSG_SIZE - 1);
    msg.data[MIPC_MSG_SIZE - 1] = '\0';

    kern_return_t kr = mach_msg(&msg.header,
                                MACH_SEND_MSG | MACH_SEND_TIMEOUT,
                                sizeof(msg),
                                0,
                                MACH_PORT_NULL,
                                100, // 100ms timeout
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

void mipc_close(mipc _Nullable bus) {
    if (!bus) return;
    pthread_mutex_lock(&bus->lock);
    bus->should_exit = true;
    pthread_mutex_unlock(&bus->lock);
    
    if (bus->is_listener && bus->local_port != MACH_PORT_NULL) {
        mipc_raw_msg_t msg = { .header = { .msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0), 
            .msgh_remote_port = bus->local_port, .msgh_size = sizeof(mach_msg_header_t) } };
        mach_msg(&msg.header, MACH_SEND_MSG, msg.header.msgh_size, 0, MACH_PORT_NULL, 0, MACH_PORT_NULL);
    }
    
    if (bus->thread) pthread_join(bus->thread, NULL);
    
    pthread_mutex_lock(&bus->lock);
    if (bus->local_port != MACH_PORT_NULL) mach_port_mod_refs(mach_task_self(), bus->local_port, MACH_PORT_RIGHT_RECEIVE, -1);
    if (bus->remote_port != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), bus->remote_port);
    pthread_mutex_unlock(&bus->lock);
    
    if (bus->group) dispatch_group_wait(bus->group, DISPATCH_TIME_FOREVER);
    pthread_mutex_destroy(&bus->lock);
    free(bus->name); free(bus);
}
