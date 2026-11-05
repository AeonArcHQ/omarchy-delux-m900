import os, select, sys, time
# Uso: python3 -I tools/listen.py /dev/hidrawN <segundos>. Imprime os input reports do receptor.
fd=os.open(sys.argv[1],os.O_RDONLY|os.O_NONBLOCK); end=time.time()+float(sys.argv[2])
while time.time()<end:
    r,_,_=select.select([fd],[],[],0.5)
    if r:
        d=os.read(fd,64); print(f"{time.time():.2f} {d.hex(' ')}", flush=True)
