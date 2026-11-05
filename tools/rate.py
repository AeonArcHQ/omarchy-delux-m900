import os, struct, sys, time
# Conta SYN_REPORT por segundo no evdev do mouse enquanto ele se move.
dev = sys.argv[1] if len(sys.argv) > 1 else "/dev/input/event4"
fd = os.open(dev, os.O_RDONLY)
fmt = "llHHi"; sz = struct.calcsize(fmt)
print("mexa o mouse sem parar por 5 segundos...", flush=True)
ts = []
end = None
while True:
    sec, usec, typ, code, val = struct.unpack(fmt, os.read(fd, sz))
    if typ == 0 and code == 0:
        t = sec + usec / 1e6
        ts.append(t)
        end = end or t + 5
        if t >= end:
            break
gaps = sorted(b - a for a, b in zip(ts, ts[1:]))
med = gaps[len(gaps) // 2]
print(f"{len(ts)} reports; mediana do intervalo {med*1000:.2f} ms ~ {1/med:.0f} Hz; pico {1/gaps[len(gaps)//10]:.0f} Hz")
