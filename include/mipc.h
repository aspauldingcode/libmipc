#ifndef MIPC_H
#define MIPC_H

#import <Foundation/Foundation.h>

/**
 * libmipc: A Secure, Sandbox-Tolerant Mach IPC Library
 *
 * Designed for high-performance communication between sandboxed and
 * non-sandboxed processes on macOS.
 */

@class NSString;

/**
 * The core MIPC connection object.
 */
typedef struct mipc_obj *mipc;

/**
 * Start listening for incoming connections.
 * 
 * @param name A unique reverse-DNS style name (e.g. "com.example.service").
 * @param on_message A block called whenever a message is received.
 * @return A mipc object, or NULL if the port is already in use.
 */
mipc _Nullable mipc_listen(const char * _Nonnull name, void (^ _Nonnull on_message)(mipc _Nonnull connection, const char * _Nonnull text));

/**
 * Connect to a known service by name.
 *
 * @param name The name of the service to connect to.
 * @param on_message Optional block to receive replies from the server.
 * @return A mipc object, or NULL if the service was not found.
 */
mipc _Nullable mipc_connect(const char * _Nonnull name, void (^ _Nullable on_message)(mipc _Nonnull connection, const char * _Nonnull text));

/**
 * Connect to a service using its broadcast key (Sandbox-Tolerant).
 * 
 * Works even when the Bootstrap server is blocked by the App Sandbox.
 *
 * @param key The common key used by the publisher.
 * @param on_message Optional block to receive replies.
 */
mipc _Nullable mipc_connect_dynamic(const char * _Nonnull key, void (^ _Nullable on_message)(mipc _Nonnull connection, const char * _Nonnull text));

/**
 * Send a UTF-8 string over a connection.
 * 
 * Messages are guaranteed to be safe and truncated to 64KB.
 *
 * @param connection The mipc object to send over.
 * @param text The string to send.
 * @return true if the message was sent successfully.
 */
bool mipc_send(mipc _Nullable connection, const char * _Nonnull text);

/**
 * Broadcast a listener's name via Global Domain Preferences (Sandbox-Tolerant).
 * 
 * Call this after mipc_listen to make the service discoverable by sandboxed clients.
 *
 * @param connection A mipc object created via mipc_listen.
 * @param key A short key for discovery (e.g. "oowm-bridge").
 */
bool mipc_publish(mipc _Nonnull connection, const char * _Nonnull key);

/**
 * Close a connection and free all associated resources.
 * 
 * This is thread-safe and waits for all pending handlers to complete.
 *
 * @param connection The mipc object to close.
 */
void mipc_close(mipc _Nullable connection);

#endif /* MIPC_H */
