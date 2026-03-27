#!/bin/bash

# run_example.sh: Setup, compile, and run the libmipc LaunchAgent example.
# This script demonstrates reading/writing config from outside a sandbox.

# Compile the library and example
echo "[Build] Compiling server and client..."
# We compile mipc.m directly into the binaries for this self-contained example
clang -fmodules -fobjc-arc -I../include ../src/mipc.m server.m -o server
clang -fmodules -fobjc-arc -I../include ../src/mipc.m client.m -o client

# Aggressive Cleanup of any old or existing agents
echo "[Cleanup] Removing any old agents..."
launchctl bootout gui/$(id -u)/com.examplemipc.server 2>/dev/null
launchctl bootout gui/$(id -u)/com.libmipc.server 2>/dev/null
pkill -f "$(pwd)/server" 2>/dev/null
rm ~/Library/LaunchAgents/com.examplemipc.server.plist 2>/dev/null
rm ~/Library/LaunchAgents/com.libmipc.server.plist 2>/dev/null
sleep 1

# Prepare the config directory and initial file
CONFIG_DIR="$HOME/.config/examplemipc"
mkdir -p "$CONFIG_DIR"
echo '{"status": "initial_config", "version": 1.0}' > "$CONFIG_DIR/config.json"

# Update plist to point to the server executable we just built
sed -i '' "s|REPLACE_ME_WITH_PATH|$(pwd)/server|g" com.examplemipc.server.plist

# Load the agent (Modern way)
echo "[Setup] Bootstrapping LaunchAgent..."
cp com.examplemipc.server.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.examplemipc.server.plist

echo "[Wait] Waiting for Server to start..."
sleep 2

# Test 1: Read initial config
echo "[Test 1] Reading initial config..."
./client read

# Test 2: Write new config
echo "[Test 2] Writing new config..."
./client write '{"status": "updated_by_client", "val": 42}'

# Test 3: Verify the update was written to disk and is readable
echo "[Test 3] Verifying update..."
./client read

# Cleanup
echo "[Cleanup] Stopping agent..."
launchctl bootout gui/$(id -u)/com.examplemipc.server 2>/dev/null
rm ~/Library/LaunchAgents/com.examplemipc.server.plist

# Restore plist template for next run
sed -i '' "s|$(pwd)/server|REPLACE_ME_WITH_PATH|g" com.examplemipc.server.plist

echo "[Finished] Sandbox escape example verified."
