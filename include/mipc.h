#ifndef LIB_MIPC_H
#define LIB_MIPC_H

#include <stdbool.h>
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

NS_ASSUME_NONNULL_BEGIN

/** A session handle representing a connection between two programs. */
typedef struct mipc_obj *mipc;

/**
 * Starts a server that others can talk to.
 *
 * @param name       A unique name for other programs to find this one.
 * @param on_message A block of code that runs whenever someone sends a message.
 * @return           A handle to manage the server, or NULL if it fails.
 */
mipc _Nullable mipc_listen(const char *name, void (^on_message)(mipc connection, const char *text));

/**
 * Connects to a server by its name.
 *
 * @param name       The name of the server you want to talk to.
 * @param on_message A block of code that runs if the server sends something back.
 * @return           A handle to manage the connection, or NULL if it fails.
 */
mipc _Nullable mipc_connect(const char *name, void (^on_message)(mipc connection, const char *text));

/**
 * Sends some text to the other end of a connection.
 *
 * @param connection The active handle to send through.
 * @param text       The message to send.
 * @return           True if it worked, false if it failed.
 */
bool mipc_send(mipc _Nullable connection, const char *text);

/**
 * Closes a connection and cleans up.
 */
void mipc_close(mipc _Nullable connection);

NS_ASSUME_NONNULL_END

#ifdef __cplusplus
}
#endif

#endif /* LIB_MIPC_H */
