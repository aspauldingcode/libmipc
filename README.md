# libmipc

| Test Suite | ARM (macOS 14) | Intel (macOS 13) |
| :--- | :--- | :--- |
| **Basic Connectivity** | [![test (macos-14)](https://github.com/aspauldingcode/libmipc/actions/workflows/ci.yml/badge.svg?branch=main&job=check%20(test,%20macos-14))](https://github.com/aspauldingcode/libmipc/actions/workflows/ci.yml) | [![test (macos-13)](https://github.com/aspauldingcode/libmipc/actions/workflows/ci.yml/badge.svg?branch=main&job=check%20(test,%20macos-13))](https://github.com/aspauldingcode/libmipc/actions/workflows/ci.yml) |
| **Security Hardening** | [![security (macos-14)](https://github.com/aspauldingcode/libmipc/actions/workflows/ci.yml/badge.svg?branch=main&job=check%20(security,%20macos-14))](https://github.com/aspauldingcode/libmipc/actions/workflows/ci.yml) | [![security (macos-13)](https://github.com/aspauldingcode/libmipc/actions/workflows/ci.yml/badge.svg?branch=main&job=check%20(security,%20macos-13))](https://github.com/aspauldingcode/libmipc/actions/workflows/ci.yml) |
| **Stress & Flooding** | [![stress (macos-14)](https://github.com/aspauldingcode/libmipc/actions/workflows/ci.yml/badge.svg?branch=main&job=check%20(stress,%20macos-14))](https://github.com/aspauldingcode/libmipc/actions/workflows/ci.yml) | [![stress (macos-13)](https://github.com/aspauldingcode/libmipc/actions/workflows/ci.yml/badge.svg?branch=main&job=check%20(stress,%20macos-13))](https://github.com/aspauldingcode/libmipc/actions/workflows/ci.yml) |
| **Dynamic Discovery** | [![discovery (macos-14)](https://github.com/aspauldingcode/libmipc/actions/workflows/ci.yml/badge.svg?branch=main&job=check%20(discovery,%20macos-14))](https://github.com/aspauldingcode/libmipc/actions/workflows/ci.yml) | [![discovery (macos-13)](https://github.com/aspauldingcode/libmipc/actions/workflows/ci.yml/badge.svg?branch=main&job=check%20(discovery,%20macos-13))](https://github.com/aspauldingcode/libmipc/actions/workflows/ci.yml) |
| **Sandbox Isolation** | [![sandbox (macos-14)](https://github.com/aspauldingcode/libmipc/actions/workflows/ci.yml/badge.svg?branch=main&job=check%20(sandbox,%20macos-14))](https://github.com/aspauldingcode/libmipc/actions/workflows/ci.yml) | [![sandbox (macos-13)](https://github.com/aspauldingcode/libmipc/actions/workflows/ci.yml/badge.svg?branch=main&job=check%20(sandbox,%20macos-13))](https://github.com/aspauldingcode/libmipc/actions/workflows/ci.yml) |

libmipc is a super simple way for two different programs on your Mac to talk to each other. It's like a private walkie-talkie system for your apps.

## How it Works (ELI5)

If you've never programmed before, here is how to think about libmipc:

- **Server**: This is the "Listener". It's like a shopkeeper waiting for customers to call.
- **Client**: This is the "Caller". It's like a customer who wants to talk to the shop.
- **Name**: This is the "Phone Number". It's a unique string (like `com.mycompany.service`) that the Client uses to find the Server.
- **Connection (Handle)**: When a Client calls a Server, they both get a "Handle". Think of this as the physical phone they are holding. You use this handle to send messages.
- **Message (Text)**: This is just a piece of text (like "Hello!") sent from one side to the other.
- **On Message (Handler)**: This is a "Rule". You tell the program: "When a message arrives, do THIS."

## API Guide (The Simple Version)

### `mipc_listen`
Starts a Server so other programs can find you.

```objc
mipc mipc_listen(const char *name, void (^on_message)(mipc connection, const char *text));
```
- **`name`**: Your "Phone Number" (e.g., `com.libmipc.server`).
- **`on_message`**: What to do when someone sends you a message.
- **Returns**: A handle to your Server.

---

### `mipc_connect`
Connects to a Server that is already running.

```objc
mipc mipc_connect(const char *name, void (^on_message)(mipc connection, const char *text));
```
- **`name`**: The "Phone Number" of the Server you want to call.
- **`on_message`**: What to do if the Server talks back to you.
- **Returns**: A handle to the connection.

---

### `mipc_send`
Sends a text message to the person on the other end.

```objc
bool mipc_send(mipc connection, const char *text);
```
- **`connection`**: The handle you are holding.
- **`text`**: The words you want to say.
- **Returns**: `true` if it worked.

---

### `mipc_close`
Hangs up the phone and cleans up.

```objc
void mipc_close(mipc connection);
```

## Quick Example

For a full project you can run, see the [example](example/) folder.

<details>
<summary><b>Server (The Shopkeeper)</b></summary>

```objc
#import <mipc.h>

int main() {
    // Start listening
    mipc server = mipc_listen("com.libmipc.server", ^(mipc customer, const char *text) {
        printf("Customer said: %s\n", text);
        
        // Reply back
        mipc_send(customer, "Thank you for calling!");
    });

    // Keep the program running
    [[NSRunLoop currentRunLoop] run];
    return 0;
}
```
</details>

<details>
<summary><b>Client (The Customer)</b></summary>

```objc
#import <mipc.h>

int main() {
    // Call the server
    mipc my_call = mipc_connect("com.libmipc.server", ^(mipc shop, const char *text) {
        printf("Server replied: %s\n", text);
    });

    // Say hello
    mipc_send(my_call, "Hi, I'm a customer!");

    // Hang up when done
    mipc_close(my_call);
    return 0;
}
```
</details>

## Sandbox Escape: Shared Configuration

A common challenge for sandboxed macOS apps is accessing configuration files in the user's home directory (e.g., `~/.config/myapp/config.json`). Since sandboxed apps are restricted to their own containers, they cannot read or write to these locations directly.

`libmipc` solves this by using a **LaunchAgent bridge**:

1.  **LaunchAgent (The Bridge)**: A non-sandboxed background process (the "Server") that has full access to the home directory.
2.  **Sandboxed App (The Client)**: Connects to the Server via `libmipc`.
3.  **Operation**: The Client sends a `get_config` or `set_config` message. The Server performs the file I/O on behalf of the Client and sends the results back.

For a complete, working demonstration of this pattern, see the [example/](example/) directory.

## License

[MIT](LICENSE)
