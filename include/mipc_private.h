#ifndef MIPC_PRIVATE_H
#define MIPC_PRIVATE_H

#import <mach/mach.h>
#import <dispatch/dispatch.h>
#import <pthread.h>
#import "mipc.h"

#define MIPC_MSG_SIZE 1024

typedef struct {
    mach_msg_header_t header;
    char data[MIPC_MSG_SIZE];
} mipc_raw_msg_t;

typedef struct {
    mipc_raw_msg_t msg;
    mach_msg_max_trailer_t trailer;
} mipc_rcv_msg_t;

struct mipc_obj {
    mach_port_t local_port;
    mach_port_t remote_port;
    void (^on_message)(mipc connection, const char *text);
    bool is_listener;
    bool should_exit;
    pthread_t thread;
    dispatch_group_t group;
};

void *mipc_worker(void *arg);

#endif /* MIPC_PRIVATE_H */
