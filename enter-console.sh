#!/bin/bash

echo "Select which console to enter:"
echo "1) Minecraft Server"
echo "2) Hytale Server"
echo "3) Playit Agent"
read -p "Enter choice [1-3]: " choice

case $choice in
    1)
        echo "Attaching to Minecraft Server... (Press Ctrl+P, Ctrl+Q to detach)"
        docker attach minecraft_server
        ;;
    2)
        echo "Attaching to Hytale Server... (Press Ctrl+P, Ctrl+Q to detach)"
        docker attach hytale_server
        ;;
    3)
        echo "Attaching to Playit Agent... (Press Ctrl+P, Ctrl+Q to detach)"
        docker attach playit_agent
        ;;
    *)
        echo "Invalid choice."
        ;;
esac
