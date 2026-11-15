#!/bin/bash
# Claude 12/11/2026: Tailscale runs inside WSL, Vivado/xsdb and Python run on Windows.
# This keeps WSL alive and forwards Windows localhost -> lab board over the WSL tailnet:
#   localhost:3122 -> <LAB_BOARD_IP>:3122 (hw_server / JTAG)
#   localhost:4002 -> <LAB_BOARD_IP>:4002 (raw TCP UART, one client at a time)
# Start from PowerShell (detached):  Start-Process wsl -ArgumentList '-u','root','-e','bash','/mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/vcu118/wsl_tailscale_bridge.sh' -WindowStyle Hidden
# Then on Windows: set VCU118_HW_SERVER=localhost:3122 for xsdb, and  python board_capture.py --tcp localhost:4002
BOARD=<LAB_BOARD_IP>
systemctl is-active --quiet tailscaled || systemctl start tailscaled
pkill -f "socat TCP-LISTEN:3122" ; pkill -f "socat TCP-LISTEN:4002"
socat TCP-LISTEN:3122,fork,reuseaddr TCP:$BOARD:3122 &
socat TCP-LISTEN:4002,fork,reuseaddr TCP:$BOARD:4002 &
exec sleep infinity
