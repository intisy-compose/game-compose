#!/bin/bash

echo "Select which console to enter:"
echo "1) Minecraft Server"
echo "2) Hytale Server"
echo "3) Playit Agent"
echo "4) Ark: Survival Evolved Server"
echo "5) Ark: Survival Ascended Server"
read -p "Enter choice [1-5]: " choice

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
    4)
        echo "Attaching to Ark: Survival Evolved Server... (Press Ctrl+P, Ctrl+Q to detach)"
        docker attach ark_ase_server
        ;;
    5)
        echo "Attaching to Ark: Survival Ascended Server... (Press Ctrl+P, Ctrl+Q to detach)"
        docker attach ark_asa_server
        ;;
    *)
        echo "Invalid choice."
        ;;
esac
