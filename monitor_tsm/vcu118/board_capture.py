"""Claude 10/11/2026 (remote mode 12/11/2026): capture the VCU118 joint-run UART (115200 8N1) until JOINT_DONE or FATAL.
   python board_capture.py                         -> lab remote board: raw TCP bridge <LAB_BOARD_IP>:4002 (default)
   python board_capture.py --tcp HOST:PORT         -> another raw TCP UART bridge
   python board_capture.py --com COM7              -> local USB-UART (needs pyserial)
The lab bridge accepts ONE TCP client at a time: close every other UART client first. Start this BEFORE
board_run_joint.tcl. Output: board_logs/uart_<time>.log (host timestamps + raw lines)."""
import sys, time, pathlib, socket, argparse

HERE = pathlib.Path(__file__).resolve().parent
(HERE / 'board_logs').mkdir(exist_ok=True)
ap = argparse.ArgumentParser()
ap.add_argument('--tcp', default='<LAB_BOARD_IP>:4002')
ap.add_argument('--com', default=None)
a = ap.parse_args()
out = HERE / 'board_logs' / time.strftime('uart_%Y%m%d_%H%M%S.log')


def lines_tcp(host, port):
    with socket.create_connection((host, port), timeout=10) as s:
        s.settimeout(1.0)
        print(f'connected to UART bridge {host}:{port}')
        buf = b''
        while True:
            try:
                d = s.recv(65536)
            except socket.timeout:
                continue
            if not d:
                raise SystemExit('bridge closed the connection')
            buf += d
            while b'\n' in buf:
                line, buf = buf.split(b'\n', 1)
                yield line


def lines_com(port):
    import serial
    h = serial.Serial(port, 115200, timeout=0.1)
    buf = b''
    while True:
        buf += h.read(4096)
        while b'\n' in buf:
            line, buf = buf.split(b'\n', 1)
            yield line


if a.com:
    src = lines_com(a.com)
else:
    host, port = a.tcp.rsplit(':', 1)
    try:
        src = lines_tcp(host, int(port))
    except OSError as e:
        sys.exit(f'cannot reach {a.tcp}: {e} (Tailscale connected? another UART client open?)')
t0 = time.time()
with open(out, 'w', newline='\n') as f:
    print('waiting for firmware output ... (Ctrl-C to stop) ->', out)
    for raw in src:
        s = raw.decode('ascii', 'replace').rstrip('\r')
        f.write(f'{time.time() - t0:10.3f} {s}\n'); f.flush()
        if not s.startswith(('P1 ', 'P2 ')):
            print(s)
        if s.startswith('JOINT_DONE') or s.startswith('FATAL'):
            print('log:', out)
            sys.exit(0 if s.startswith('JOINT_DONE') else 1)
