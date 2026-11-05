import fcntl, os, select, sys, time
# uso: sendfeat.py /dev/hidrawN "06 09 01 33 cc 00 00 00 00" [segundos]
dev, hexs = sys.argv[1], sys.argv[2]
secs = float(sys.argv[3]) if len(sys.argv) > 3 else 3
buf = bytearray(bytes.fromhex(hexs))
HIDIOCSFEATURE = lambda n: (3 << 30) | (n << 16) | (ord('H') << 8) | 0x06
fd = os.open(dev, os.O_RDWR)
r = fcntl.ioctl(fd, HIDIOCSFEATURE(len(buf)), buf)
print(f"{time.time():.2f} enviado {hexs} -> ioctl {r}")
end = time.time() + secs
while time.time() < end:
    rl, _, _ = select.select([fd], [], [], max(0, end - time.time()))
    if rl:
        print(f"{time.time():.2f} " + os.read(fd, 64).hex(" "))
os.close(fd)
