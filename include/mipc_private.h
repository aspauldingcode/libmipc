#ifndef MIPC_PRIVATE_H
#define MIPC_PRIVATE_H

#include <mach/mach.h>
#include <pthread.h>

// Private sandbox function declarations needed by the client.
char *sandbox_extension_issue_mach_to_process(const char *extension_class, const char *name, uint32_t flags, audit_token_t);
char *sandbox_extension_issue_mach(const char *extension_class, const char *name, uint32_t flags);
int64_t sandbox_extension_consume(const char *extension_token);
int sandbox_extension_release(int64_t extension_handle);
extern const char *APP_SANDBOX_MACH;

// Internal worker thread function.
void *mipc_worker(void *arg);


// The internal structure for a mipc object.
typedef struct mipc_obj {
    mach_port_t local_port;
    mach_port_t remote_port;
    char *name;
    bool is_listener;
    bool should_exit;
    pthread_t thread;
    pthread_mutex_t lock;
    dispatch_group_t group;
    void (^on_message)(struct mipc_obj *connection, const char *text);
} mipc_obj_t;

// Message structures for Mach communication.
typedef struct {
    mach_msg_header_t header;
    char data[65536];
} mipc_raw_msg_t;

typedef union {
    mipc_raw_msg_t msg;
    char buffer[sizeof(mipc_raw_msg_t)];
} mipc_rcv_msg_t;

#endif /* MIPC_PRIVATE_H */
