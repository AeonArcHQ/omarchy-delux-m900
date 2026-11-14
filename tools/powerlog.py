import os, select, sys, time
# Usage: python3 -I tools/powerlog.py /dev/hidrawN <seconds>. Logs each change of the power report (03 xx 40 b3 b4)
# with a timestamp, prints other report-3 events raw, and writes a heartbeat every 60 s.
fd = os.open(sys.argv[1], os.O_RDONLY | os.O_NONBLOCK); start = time.time(); end = start + float(sys.argv[2])
last = None; beat = start; n = 0
while time.time() < end:
    if select.select([fd], [], [], 0.5)[0]:
        d = os.read(fd, 64)
        if len(d) >= 5 and d[0] == 3 and d[2] == 0x40:
            n += 1
            if (d[3], d[4]) != last:
                last = (d[3], d[4]); print(f"{time.strftime('%H:%M:%S')} +{time.time()-start:5.0f}s state={d[3]} level={d[4]}", flush=True)
        elif len(d) >= 3 and d[0] == 3:
            print(f"{time.strftime('%H:%M:%S')} other {d.hex(' ')}", flush=True)
    if time.time() - beat >= 60:
        beat = time.time(); print(f"{time.strftime('%H:%M:%S')} heartbeat reports={n} last={last}", flush=True)
print("done", flush=True)
