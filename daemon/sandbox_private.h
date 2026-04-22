#ifndef SANDBOX_PRIVATE_H
#define SANDBOX_PRIVATE_H

#import <mach/mach.h>

// From the private `sandbox.h` header.

// Issues a token bound to a specific process via its audit token.
char *sandbox_extension_issue_mach_to_process(const char *extension_class, const char *name, uint32_t flags, audit_token_t);

// Issues a general token.
char *sandbox_extension_issue_mach(const char *extension_class, const char *name, uint32_t flags);

// Consumes a token, returning a handle.
int64_t sandbox_extension_consume(const char *extension_token);

// Releases the handle from a consumed token.
int sandbox_extension_release(int64_t extension_handle);

// Required constant for the extension class.
extern const char *APP_SANDBOX_MACH;

#endif /* SANDBOX_PRIVATE_H */
