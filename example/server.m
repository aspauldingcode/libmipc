#import <Foundation/Foundation.h>
#import "../include/mipc.h"
#import <unistd.h>

/**
 * Example Secure Server (Bridge)
 * Acts as a middleman for sandboxed apps to read/write files in the home directory.
 */

static NSString *getConfigPath() {
    NSString *home = NSHomeDirectory();
    NSString *configDir = [home stringByAppendingPathComponent:@".config/examplemipc"];
    [[NSFileManager defaultManager] createDirectoryAtPath:configDir withIntermediateDirectories:YES attributes:nil error:nil];
    return [configDir stringByAppendingPathComponent:@"config.json"];
}

int main() {
    @autoreleasepool {
        printf("[Server] Starting secure bridge: com.examplemipc.server\n");
        
        mipc listener = mipc_listen("com.examplemipc.server", ^(mipc connection, const char *text) {
            NSString *input = [NSString stringWithUTF8String:text];
            printf("[Server] Received: %s\n", text);
            
            if ([input isEqualToString:@"get_config"]) {
                NSError *error = nil;
                NSString *content = [NSString stringWithContentsOfFile:getConfigPath() encoding:NSUTF8StringEncoding error:&error];
                if (!content) content = @"{}";
                mipc_send(connection, [content UTF8String]);
            } 
            else if ([input hasPrefix:@"set_config "]) {
                NSString *json = [input substringFromIndex:11];
                NSError *error = nil;
                BOOL success = [json writeToFile:getConfigPath() atomically:YES encoding:NSUTF8StringEncoding error:&error];
                mipc_send(connection, success ? "success" : "failure");
            }
            else if (strcmp(text, "ping") == 0) {
                mipc_send(connection, "pong");
            }
        });
        
        if (!listener) {
            fprintf(stderr, "[Server] Error: Could not start listener.\n");
            return 1;
        }
        
        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
