# Reverse engineering: DELUX Gaming Driver 20260128

Findings log with REA Evidence IDs. Each item says whether it was **observed** (in the binary or on the hardware), **inferred**, or is **unknown**.

## Artifacts

| File | SHA-256 | Source |
|---|---|---|
| `DELUX Gaming Driver.exe` (Inno Setup 6.1 installer, unicode) | `b987e3af…323b2e` | `DELUX Gaming Driver-M900Pro ultra-light version.rar`, from the DELUX website |
| `app/DELUX.exe` (DuiLib UI, x86) | `2d1f3770…4715f` | extracted with `innoextract` |
| `app/hiddriver_*.dll` (24 identical copies) | `f9efbf06…39f4` | extracted with `innoextract` |

## hiddriver.dll: HID transport

- **Observed**: exports `Set_VIDPID`, `Open_DevMonitor`/`Close_DevMonitor`, `Open_FeatureDevice`/`Close_FeatureDevice`, `SetFeature`/`GetFeature`, `Hid_Read`/`Hid_Write` (`ev_7f3fb508…`).
- **Observed**: `SetFeature` and `GetFeature` pass the buffer straight to `HidD_SetFeature` and `HidD_GetFeature`. The first byte is the report ID (`ev_a215a786…`).
- **Observed**: the interface is chosen from HIDP_CAPS (`ev_79e9a278…`):
  - for the input/output channel: UsagePage `0x000A`, Usage `0`, VID/PID equal to those given to `Set_VIDPID`;
  - for the feature channel: UsagePage `0x000B`, Usage `0`, same VID/PID.

## Hardware on this machine (observed on 2026-10-22)

The `1d57:fa60` receiver shows up as "LXDDZ 2.4G Wireless Device", with 4 interfaces. `hidraw2` (interface 1.2) has:

- a UsagePage `0x0A` collection: input report ID `0x03`, 4 bytes;
- a UsagePage `0x0B` collection: feature reports. Length of each, not counting the ID:
  `0x04`=55, `0x05`=14, `0x06`=8, `0x07`=7, `0x08`=58, `0x09`=63, `0x0A`=7, `0x0B`=7, `0x0C`=9, `0x10`=7, `0xA0`=7, `0x22`=63.

Command: `od -An -tx1 -v /sys/class/hidraw/hidraw2/device/report_descriptor`

## DELUX.exe: models and VID/PID

- **Observed**: the main window constructor, `sub_40f8f0`, creates one object per model and stores a pair in it (wired VID/PID, receiver VID/PID) (`ev_3a69c6ef…`):

  | Object (vtable) | Wired | Receiver |
  |---|---|---|
  | `0x523a…` (1st) | 1d57:fa61 | 1d57:fa60 |
  | `0x54544c` | 1d57:fa71 | 1d57:fa60 |
  | `0x545e08` | 1d57:fa72 | 1d57:fa60 |
  | `0x548d54` | 1d57:fa73 | 1d57:fa60 |
  | `0x54a9d4` | 1d57:fa74 | 1d57:fa60 |
  | `0x54c68c` | 1d57:fa75 | 1d57:fa60 |
  | `0x54e374` | 1d57:fa76 | 1d57:fa60 |
  | `0x551d3c` | 1d57:fa78 | 1d57:fa60 |
  | `0x5268f4` (ms_10) | 1d57:fa79 | 1d57:fa60 |

  More models are built in `sub_42cc00`, `sub_4391f0` and the following functions, not read yet.
- **Observed**: when a device arrives, `VID_1D57&PID_FA60` arms timer `0x36` and `PID_FA65` arms timer `0x37` (`sub_413c60`, `ev_5f15a739…`).
- **Inferred**: several models share the `fa60` receiver. So the paired mouse's model cannot be derived from the receiver PID and has to be queried (through the wired PID or some identification report).

## Identifying the paired mouse (resolved)

- **Observed (code)**: `sub_415ef0` uses `hid_enumerate(0x1d57, 0xfa60)`. It opens the UsagePage `0x0B` collection as "handle" (feature report commands) and the `0x0A` one as "OSD handle" (input reports). One thread per slot calls `hid_read`, in `sub_416720` (`ev_952694…`).
- **Observed (code)**: byte 1 of input report 3 is the model code. A table maps the code to the model index, and index `i` matches `device_{i+1}_text` and class `MS_{i+1}`:
  `10→0 20→1 21→2 30→3 31→4 32→5 33→6 34→7 35→8 36→9 37→10 38→11 39→12 3a→13 3d→14 3f→15 29→16 2a→17 2b→18 2c→19 50→20 2e→21 2d→22 56→23`.
- **Observed (code)**: index 14 stores the hidapi handle in field `[0x477e2]` of the object at `+0x8c4190`. That is the object built by `sub_458200` (`MS_15`), the same field the 2.4G branch of `sub_45e200` uses (`ev_ebe506d4…`, `ev_2820d7c0…`).
- **Observed (hardware)**: the receiver sends `03 3d 40 03 46` every ~2 s on `/dev/hidraw2`.
- **Conclusion**: the mouse is **`MS_15` = "M900PRO"**, wired `1d57:fa24`, 2.4G receiver `1d57:fa60` and Bluetooth `VID&02045E PID&0033D`.

## Input report 3 (UsagePage 0x0A): state events (resolved for battery)

Format: `03 <model> <event> <b3> <b4>`. `sub_4171a0` builds `arg0 = b2<<8 | b1` and `arg4 = b4<<8 | b3`, and `sub_45d4c0` dispatches on the event (`ev_90436d5c…`, `ev_643a23ed…`):

| Event (byte 2) | Meaning | Source |
|---|---|---|
| `0x10` | DPI stage changed; `arg4` (1–8) is the active stage | observed |
| `0x20` | polling rate changed; index `(arg4 & 0x0f) - 1` | observed |
| `0x40` | **power**: `b3` is the state, `b4` is the percentage | observed |
| `0x50` | command ACK: `arg4 == 0` means success (flag `[0x113]`) | observed |
| `0x60` | value ≤ 10 stored in the same field as the battery level (`[0x5d]`) | observed; meaning inferred |
| `0x70` | light mode: `(arg4 >> 4) & 0x0f` | observed |
| `0x80` | `arg4` ≤ 5: reloads the configuration (profile?) | observed; meaning inferred |

Power state (`b3`, event `0x40`):
- `2`: fully charged. The UI shows 100%.
- `3`: charging. The UI animates "charging", and `b4` still carries the level.
- others: discharging. The UI shows `b4` when 1 ≤ `b4` ≤ 100.

Real readings on 2026-10-22 (`python3 -I tools/listen.py /dev/hidraw2 10`):
- with the cable: `03 3d 40 03 46` = M900PRO, charging, 70%;
- without the cable: `03 3d 40 01 4d` = M900PRO, in use (`b3=1`), 77%. This confirms that `b3=1` is the normal state and `b4` is the level.

The app marks the mouse as disconnected after 6 s without an input report (timer `0x2e0`, 6000 ms).


## Configuration commands (feature reports, MS_15)

### General rules

- **Observed**: in 2.4G mode, `sub_45e200` calls `hid_send_feature_report(handle_0x0B, buf, len)` with the buffer as is and waits for the ACK of event `0x50` (`ev_1a0c4265…`).
- **Observed**: `DELUX.exe` only imports `hid_send_feature_report`, `hid_write`, `hid_read`, `hid_enumerate`, `hid_open_path`, `hid_set_nonblocking`, `hid_init` and `hid_free_enumeration`. **It does not import `hid_get_feature_report`** (`ev_efe7fdb5…` and `list_names`). So over 2.4G the app never reads the mouse's configuration: it writes it and tracks the state through report 3 events.
- **Observed**: every command has the form `[reportID][total length][0x01][data…][checksum]`. The checksum is the 16-bit sum of the bytes from index 3 to the end of the data, stored **big-endian** (high byte first). Reports 4, 5 and 8 use this scheme; report 6 uses the byte's complement.
- **Observed**: `sub_45e910` compares the new profile with the last one applied and sets per-group "dirty" flags. Then `sub_45ecc0` sends only the reports of the groups that changed (`ev_d013f2af…`, `ev_a904d08f…`).
- The lengths match the descriptor: report 4 = 0x38 (1+55), report 5 = 0x0f (1+14), report 6 = 0x09 (1+8), report 8 = 0x3b (1+58), report 0x0C = 0x0a (1+9).

Map from profile fields to UI controls. It comes from the handlers `sub_45b030`, `sub_45b250`, `sub_45b350`, `sub_45b660` and `sub_45bd90` (`ev_50f575f9…`), the init `sub_458580` (`ev_55de26c0…`) and the ranges in `res/MS/MS_15/ms_15_page.xml`.

| Profile field | Control | Range |
|---|---|---|
| `+0x8c4 + 4i` (i=0..7) | `ms_15_slider_dpi_{i+1}` | 1–520, DPI = value × 50 (50–26000) |
| `+0x904 + 4i` | `ms_15_check_dpi_step_{i+1}` (stage enabled/disabled) | 0/1 |
| `+0x934` | `ms_15_option_dpi_step_*` (current stage) | 0–7 |
| `+0x968 + 4i` | color of stage i (bytes R,G,B) | 0–255 each |
| `+0x938` | `ms_15_btn_prate_*`: 125/250/500/1000 Hz | 0–3 |
| `+0x93c` | `ms_15_btn_prate_hs_*`: 125/250/500/1000/2000/4000/8000 Hz | 0–6 |
| `+0x8b4` | `ms_15_option_lift_of_distance_*`: 1 mm / 2 mm | 0–1 |
| `+0x944` | ripple control (off/on) | 0–1 |
| `+0x948` | angle snapping (off/on) | 0–1 |
| `+0x94c` | motion sync (off/on) | 0–1 |
| `+0x950` | sensor mode: HP / LP / office (hidden) / corded | 0–3 |
| `+0x954` | `ms_15_combo_light` (light mode) | 0–11 |
| `+0x924` | brightness | 1–8 |
| `+0x928` | breathing speed | 4–8 |
| `+0x92c` | sleep timer (min) | 1–60 |
| `+0x930` | light off after (min) | 1–60 |
| `+0x960` | key response time / debounce (ms) | 1–50 |
| `+0x964..0x966` | light color (R,G,B) | 0–255 |

Light modes (`EN.xml`, `ms_lightmode1..12`): 0 LED Off, 1 Static, 2 Breathing, 3 Neon, 4 Color Breathing, 5 Color Static, 6 Mixed Breathing, 7 Rainbow Wave, 8 Lightning, 9 Static Mixed Color, 10 Marquee, 11 Marquee 2.

### Report 0x04: DPI and sensor (`sub_45f070`, `ev_9ba2d983…`), 56 bytes

| Index | Content |
|---|---|
| 0–2 | `04 38 01` |
| 3 | `(lift << 4) \| ripple` |
| 4 | `(angle_snap << 4) \| motion_sync` |
| 5 | bitmask of enabled stages (bit i = stage i) |
| 6 | sensor mode |
| 7 | `00` |
| 8–15 | low byte of `(dpi_i/50 − 1)`, i=0..7 |
| 16–23 | high byte of `(dpi_i/50 − 1)` |
| 24 | current stage + 1 |
| 25–48 | 8 × (R,G,B) stage colors |
| 49 | `03` |
| 50–51 | BE checksum of the sum of bytes 3..49 |
| 52–55 | `00` |

### Report 0x05: light, sleep and debounce (`sub_45ecc0`), 15 bytes

| Index | Content |
|---|---|
| 0–2 | `05 0f 01` |
| 3 | `light_mode << 4` |
| 4 | `(sleep & 0xF0) \| (9 − speed)` |
| 5 | `((sleep << 4) & 0xFF) \| brightness` when the mode is 1 (Static) or 9 (Static Mixed Color); otherwise `((sleep << 4) & 0xFF) \| 8` |
| 6–8 | color R, G, B |
| 9 | light off after (min) |
| 10 | debounce (ms) |
| 11–12 | BE checksum of the sum of bytes 3..10 |
| 13–14 | `00` |

The sleep timer is split into two nibbles: the high nibble goes in byte 4 and the low one in the high nibble of byte 5. This is **observed** in the assembly (`0x45ee0c`–`0x45ee4a`).

### Report 0x06: polling rate (`sub_45ecc0`), 9 bytes

`06 09 01 X ~X 00 00 00 00`, with `X = ((idx_hs + 1) << 4) | (idx_normal + 1)` and `~X` = bitwise complement. This matches event `0x20`, where the index is `(arg4 & 0x0F) − 1`.

### Report 0x0C (`sub_45ecc0`), 10 bytes

`0c 0a 01 fe 01 fe 00 00 00 00`. Sent when `[obj+0xf8300] == 1`. That flag is set when switching profiles in the list (`sub_45b250`), and in that case every group is marked dirty. **Inferred**: a "rewrite everything / switch profile" header. The exact meaning is **unknown**.

### Report 0x08: button functions (`sub_45f830`, `ev_04305075…`), 59 bytes

- `08 3b 01`, then 18 entries of 3 bytes (indices 3..56), one per button. The BE checksum of the sum of bytes 3..56 sits at indices 57–58.
- Each button's data lives in the profile at `+0x9a8 + n·0x1020`. Byte `+1` is the function's internal ID.
- The ID goes through a table at `0x519730` (0x14-byte entries: `id, b0, b1, b2`; `ev_ec63ad67…`), which yields the 3 bytes sent. Observed exceptions:
  - ID `0x10` (keyboard shortcut): `b1` = modifier (`+0x9af`), `b2` = key (`+0x9ab`);
  - IDs `0x11` and `0x19` (macro): `b1 = 0` and `b2` = macro index (`obj+0x11df98`).
- **Observed**: entries with `b0 = 0x11` are predefined keyboard shortcuts, with the HID modifier in `b1` and the HID usage in `b2`: `01 1b` = Ctrl+X, `01 06` = Ctrl+C, `01 19` = Ctrl+V, `04 2b` = Alt+Tab, `08 07` = Win+D, `04 3d` = Alt+F4, `08 15` = Win+R, `08 0f` = Win+L, `0a 16` = Win+Shift+S.
- Full decoded table: `scratchpad/re/keytable_0x519730.hex`. The lookup in `sub_45f830` starts at `0x519734` and compares `[eax-4]` with the ID; so each entry is `id, b0, b1, b2, extra` as dwords (`ev_04305075…`, `ev_bdb23f98…`). An ID with no entry yields `00 00 00`.

#### Internal IDs, menu items and bytes sent (observed)

The menu handler `sub_45c740` (`ev_b686bd13…`) compares the name of the clicked item and stores the ID at `+0x9a9` of slot `[obj+0x11de78]` (0..16). Combined with table `0x519730`:

| Menu item | ID | `b0 b1 b2` |
|---|---|---|
| `ms_15_button_off` | 0x00 | `01 00 00` |
| `ms_15_click` (left) | 0x01 | `02 00 00` |
| `ms_15_menu` (right) | 0x02 | `03 00 00` |
| `ms_15_scroll` (middle) | 0x03 | `04 00 00` |
| `ms_15_forward` | 0x04 | `06 00 00` |
| `ms_15_backward` | 0x05 | `05 00 00` |
| `ms_15_dpi_cycle` / `dpi_up` / `dpi_down` | 0x06 / 0x07 / 0x08 | `0d` / `0e` / `0f` |
| `ms_15_double_click` | 0x09 | `07 00 00` |
| `ms_15_fire_button` | 0x0a | `08 00 00` |
| `ms_15_scroll_up` / `scroll_down` | 0x0b / 0x0c | `09` / `0a` |
| `ms_15_titl_left` / `titl_right` | 0x0d / 0x0e | `0b` / `0c` |
| `ms_15_shortcut` | 0x10 | `11 <modifier> <usage>` |
| `ms_15_select_macro` | 0x11 | `12 00 <macro>` |
| `ms_15_easy_aim` / `led_loop` | 0x16 / 0x17 | `10 00 03` / `29 00 03` |
| media: player, play/pause, stop, previous, next, vol+, vol−, mute | 0x40–0x47 | `15 18 19 16 17 1b 1c 1a` |
| browser: home, favorites, forward, back, stop, refresh, search | 0x50–0x56 | `25`, `11 03 12` (Ctrl+Shift+O), `20 21 22 24 26` |
| e-mail, calculator, my computer | 0x57–0x59 | `1e 1d 23` |
| cut, copy, paste, open, save, find, redo | 0x20–0x26 | `11 01 1b`, `11 01 06`, `11 01 19`, `11 01 12`, `11 01 16`, `11 01 09`, `11 01 1c` |
| select all, print | 0x28, 0x29 | `11 01 04`, `11 01 13` |
| close window, switch windows, show desktop | 0x2a–0x2c | `11 04 3d` (Alt+F4), `11 04 2b` (Alt+Tab), `11 08 07` (Win+D) |
| run, lock, screenshot | 0x2d, 0x2e, 0x32 | `11 08 15`, `11 08 0f`, `11 0a 16` |

Before storing, the handler checks that some slot still has the left click (ID 1). If none does, it shows `oneclicktext` and stores nothing.

#### Slots and physical buttons (observed)

- `sub_4607c0` (`ev_1adbb900…`) fills the 18 slots with the IDs from the dword table at `0x519c90` (`ev_c4f5cf02…`): `1, 2, 3, 6, 0x18, 4, 5, 0x34, 0×8, 0x0b, 0x0c`. Byte `+0x9aa` comes from `0x519c48`, which is all zeros.
- `ms_15_page.xml` lists the buttons with their drawing number (`mouse/N.png`). Visible: `key_1` → 1, `key_2` → 2, `key_3` → 3, `key_6` → 4, `key_7` → 5. Hidden: `key_4` (number 6) and `key_5`, `key_8`…`key_18`.
- From the drawing (`skins/ms_15/mouse.png` with `mouse_control_N.png`): 1 = left, 2 = right, 3 = wheel, 4 = front side, 5 = back side, 6 = DPI button behind the wheel.
- So the factory report 0x08 is: slot 1 `02`, slot 2 `03`, slot 3 `04`, slot 4 `0d` (DPI), slot 5 `28`, slot 6 `06` (forward), slot 7 `05` (back), slot 8 `3c`, slots 9–16 `01` (off), slot 17 `09` (wheel up), slot 18 `0a` (wheel down).
- **Unknown**: the functions of IDs 0x18 (`28`) and 0x34 (`3c`), which sit in hidden slots.

### Validation with the mouse owner (2026-10-22)

- **Sleep**: with the mouse awake, commands got ACKs again. This confirms that the missing ACK came from the mouse being asleep.
- **Light from the panel**: static blue and then red.
- **DPI from the panel**: 400 made the cursor slow and 3200 fast. The mouse's DPI button moved the panel's selection to the next stage (5000).
- **Report 0x08**: `083b01 020000 030000 040000 0d0000 280000 1b0000 050000 3c0000 010000×8 090000 0a0000 00b5` (factory, with slot 6 = `1b`) got an ACK. The front side button started raising the volume, and left, right, wheel, back side and scrolling stayed the same. From the panel: front side = forward (`06`) and back side = Ctrl+C (`11 01 06`) worked. This confirms the slot order, the native codes and the shortcut format.

### Report 0x09: macros (`sub_45f3e0`)

Builds a 111-byte `09 6f …` buffer, but the descriptor declares report 9 with 63 data bytes. How the send is split over 2.4G is **unknown**. Out of the initial scope.

## Hardware validation (2026-10-22)

Polling (report 0x06) was validated on Linux through `HIDIOCSFEATURE` on `/dev/hidraw2`, with `python3 -I tools/sendfeat.py /dev/hidraw2 "<hex>"`:
- `06 09 01 33 cc 00 00 00 00` (500 Hz): ACK `03 3d 50 00 06`, that is, event 0x50, status 0 and report 06. Measured with `sudo python3 -I tools/rate.py /dev/input/event4`: median of 2.00 ms, about **500 Hz**.
- `06 09 01 44 bb 00 00 00 00` (1000 Hz): ACK `03 3d 50 00 06`. Measured: median of 1.00 ms, about **999 Hz**.
- The ACK carries the confirmed report ID in byte 4. Event 0x20 is **not** emitted when the change comes from the host.
- Report 0x04 (DPI) was sent through `tools/m900build.py dpi`: ACK `03 3d 50 00 04`. With 5 stages enabled and the current stage at 3, the DPI button produced `03 3d 10 0N 00` with N = 4, 5, 1, 2, 3… This confirms the stage bitmask, the current index and the cycle. The mouse owner confirmed that the cursor speed changes. Log: `scratchpad/re/teste_dpi_luz.log`.
- Report 0x05 (static green light) was sent through `tools/m900build.py light`: ACK `03 3d 50 00 05`. The LED turned green.
- Color order **confirmed as RGB**. With the static light at `ff 00 00`, the LED turned red. Then the DPI button went to stage 4 (event `03 3d 10 04 00`, 3200 DPI), and the LED turned green, the `(0,255,0)` color set for that stage, with a fast cursor. Then the LED went back to the static light's red, and the DPI stayed at 3200. So the stage color only flashes when the DPI changes, and then the light mode's color comes back. In the first test the static light was also green, which is why the colors looked the same.

## Factory default profile (`sub_4607c0`, `ev_1adbb900…`)

This is the "restore" button routine. Then `sub_4592f0` refreshes the UI and the flag `[0xf8300]=1` rewrites everything, starting with report 0x0C. **Observed** values:

- **DPI** (value × 50): 400, 800, 1200, 1600, 3200, 5000 enabled; stages 7 and 8 off (value 0). Current stage: index 1 (800).
- **Stage colors** (dword `0x00BBGGRR`, sent as R,G,B): red, green, blue, magenta, yellow, white, orange `ff 40 00`, white.
- **Polling**: normal at index 3 (1000 Hz); high speed at index 6 (8000 Hz).
- **Sensor**: lift 1 mm, ripple **on**, angle snap off, motion sync **on**, sensor mode 3 ("corded").
- **Light**: mode 7 = **Rainbow Wave**, brightness 8, speed 6, color `0xff0000` = blue (`00 00 ff`), light off after 2 min.
- **Timers**: sleep 10 min, debounce 3 ms.
- **Buttons**: 18 entries filled from tables in `.rdata`, decoded in "Slots and physical buttons" (factory report 0x08).

### Factory restore from Linux (2026-10-22)

The "restore" button sequence was sent with `tools/sendfeat.py`: `0c 0a 01 fe 01 fe 00 00 00 00`, then report 0x04 with the factory defaults (stages 7 and 8 off in the bitmask), 0x05 (`05 0f 01 70 03 a8 00 00 ff 02 03 02 1f 00 00`, Rainbow Wave) and 0x06 (`06 09 01 74 8b 00 00 00 00`, 1000/8000 Hz). All four got ACK `03 3d 50 00 <id>`, including 0x0C. Log: `scratchpad/re/aplica_fabrica.log`.

### Commands while the mouse sleeps (2026-10-22, observed)

About 20 minutes after the restore, with nobody touching the mouse (10 min sleep timer), `sendfeat.py` with `06 09 01 74 8b 00 00 00 00` got **no** ACK within 3 s. The receiver kept sending `03 3d 40 01 4a` every 2 s. **Inferred**: while the mouse sleeps, the receiver repeats the last power state and does not forward commands. So the mouse being asleep does not show up as report 3 going silent, and the panel treats a missing ACK as "move the mouse and try again". **To confirm**: whether the command goes through after waking the mouse, and whether the repeated level goes stale during sleep.
- **Light modes** (the mouse owner watching the LED): Static stays fixed on the light color. Breathing fades out and in slowly on the light color. Neon cycles through all colors. Color Breathing breathes while changing color. Modes 5 to 11 (Color Static, Mixed Breathing, Rainbow Wave, Lightning, Static Mixed Color, Marquee, Marquee 2) light up in the current DPI stage's color and ignore the light color: with the light set to magenta, the LED turned green, the color of stage 2. On the next DPI change, the LED flashes the new color and **turns off** until the mode is sent again. This happened with the DPI changed by the host (stage 1, red) and by the mouse button (stage 3, blue). In Static, a DPI change flashes the stage color and goes back to the light color. **Inferred**: the M900 Pro has a single LED, and these multi-zone effects have nothing to show. That is why the factory profile, in Rainbow Wave, leaves the LED off after report 0x04 arrives.
- **The driver sends nothing extra for these modes** (observed): `sub_45ecc0` (`ev_a904d08f…`) applies the profile by sending only `0x0C`, `0x04`, `0x05`, `0x06`, `0x08` and the `0x09` macros. The light mode only changes report 0x05, in the high nibble of byte 3 and in the brightness, which is sent only in modes 1 and 9. The sender `sub_45e200` has 11 callers (`ev_7a0ba7d3…`). The ones outside the MS_15 block that I checked are copies of the same routine for other models (`sub_471600` = MS_17, `ev_e07bb4a2…`, with the same reports). The rest (`0x4a1550`, `0x4a1900`, `0x4a1c70`, `0x4bcba0`, `0x4bcf50`) were not opened. So with the Windows driver, Rainbow Wave and the other modes 5–11 should behave the same. **To confirm** by running the official driver.
- **Timers from the panel**: with "light off after" at 1 min, the LED turned off with the mouse idle. With sleep at 2 min, a send made ~1 min 45 s after the last command gave `timeout`, and got ACKs again after moving the mouse.
- **Polling from the panel**: 500 Hz (`06 09 01 73 8c …`, high speed at 8000) measured as ~500 Hz (2361 reports in 5 s, peak of 513 Hz) with `rate.py` on `/dev/input/event4`.
- **Effect not validated** (ACK only): lift-off, sensor mode, motion sync, ripple and debounce. Angle snapping: with it on, hand-drawn vertical strokes in Pinta did not come out visibly straighter (inconclusive test; the feature only corrects small deviations).
