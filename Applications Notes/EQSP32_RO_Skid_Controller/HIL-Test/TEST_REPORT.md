# EQSP32 Reverse Osmosis Skid - HIL Test Report

- **Date:** 2026-06-15 10:47:36
- **Device:** EQSP32 (ESP32-S3) on COM35, firmware `EQSP32_RO_Skid_Controller` (HIL build)
- **Specification:** Reverse Osmosis Skid - Control & Operation Specification v0.3
- **Method:** All sensors injected and all outputs read back over the EQSP32 HIL serial protocol; controller state, LED indication and outputs verified from `>>STATE` telemetry and output-cache queries.
- **Note:** Long process timers are time-compressed in the HIL build (flush interval 8 s, flush 2 s, TDS-trip 3 s, settle/min-on/min-off/dry-run grace 1.5 s). Control logic and setpoints are identical to production.

## Result: 31 / 31 checks passed  (ALL PASS)

| # | Test | Expected | Actual | Result |
|---|------|----------|--------|--------|
| 1 | A1: Run/Stop=STOP with healthy sensors -> safe STOP, LED off | st=STOP pump=0 sv=0 fv=0 led=OFF | st=STOP pump=0 sv=0 fv=0 led=OFF | PASS |
| 2 | A2: Run/Stop=RUN -> auto-start through STARTING to RUNNING (no operator start) | st=RUNNING pump=1 sv=1 fv=0 led=GREEN | st=RUNNING pump=1 sv=1 fv=0 led=GREEN | PASS |
| 3 | A3: Output cache cross-check (pump/supply/flush POUT duty) | EQ.15=1000 EQ.16=1000 EQ.14=0 | EQ.15=1000 EQ.16=1000 EQ.14=0 | PASS |
| 4 | B1: Clean tank full (>=400) -> stop, IDLE_FULL, blue solid | st=IDLE_FULL pump=0 led=BLUE/SOLID | st=IDLE_FULL pump=0 led=BLUE blink=SOLID | PASS |
| 5 | B2: Clean 385 (between 380-400) -> hysteresis holds, stays stopped | st=IDLE_FULL pump=0 | st=IDLE_FULL pump=0 cln=385 | PASS |
| 6 | B3: Clean falls to 375 (<=380) -> auto restart to RUNNING | st=RUNNING pump=1 | st=RUNNING pump=1 cln=375 | PASS |
| 7 | B4: Supply tank low (<50) -> pause, PAUSE_SUPPLY, blue blink | st=PAUSE_SUPPLY pump=0 led=BLUE/BLINK | st=PAUSE_SUPPLY pump=0 led=BLUE blink=BLINK | PASS |
| 8 | B5: Supply 55 (between 50-60) -> hysteresis holds, stays paused | st=PAUSE_SUPPLY pump=0 | st=PAUSE_SUPPLY pump=0 sup=55 | PASS |
| 9 | B6: Supply rises to 65 (>=60) -> auto resume to RUNNING | st=RUNNING pump=1 | st=RUNNING pump=1 sup=65 | PASS |
| 10 | C1: Feed pressure >200 with normal flow -> early-fouling WARNING (yellow slow) | warn=HP led=YELLOW/SLOW | warn=HP led=YELLOW blink=SLOW pin=210 | PASS |
| 11 | C2: Feed pressure >200 with low permeate -> CLEANING REQUIRED (yellow fast) | warn=CLEAN led=YELLOW/FAST | warn=CLEAN led=YELLOW blink=FAST pin=210 perm=1.8 | PASS |
| 12 | C3: Low feed flow (<8 L/min) -> flow WARNING (yellow medium) | warn=FLOW led=YELLOW/MED | warn=FLOW led=YELLOW blink=MED feed=4.6 | PASS |
| 13 | C4: Recovery out of band (>30%) -> recovery WARNING (yellow medium) | warn=REC led=YELLOW/MED | warn=REC led=YELLOW blink=MED rec=35 | PASS |
| 14 | C5: Rising permeate TDS (>160, <200) -> TDS WARNING (yellow fast) | warn=TDS led=YELLOW/FAST | warn=TDS led=YELLOW blink=FAST tdso=180 | PASS |
| 15 | D1: Motor over-temperature (>=80C) -> FAULT, red, pump off | fault=TEMP fcode=1 pump=0 led=RED | st=FAULT fault=TEMP fcode=1 pump=0 led=RED | PASS |
| 16 | D1c: Run/Stop=STOP clears the over-temperature fault | fault=NONE st=STOP | st=STOP fault=NONE | PASS |
| 17 | D2: Dry-run / no feed flow (>grace) -> FAULT, code 2 | fault=DRYRUN fcode=2 pump=0 | st=FAULT fault=DRYRUN fcode=2 pump=0 | PASS |
| 18 | D2c: Run/Stop=STOP clears the dry-run fault | fault=NONE st=STOP | st=STOP fault=NONE | PASS |
| 19 | D3: Permeate TDS >200 sustained (>=10 min, test 3s) -> FAULT, code 3 | fault=TDS fcode=3 pump=0 | st=FAULT fault=TDS fcode=3 pump=0 tdso=210 | PASS |
| 20 | D3c: Run/Stop=STOP clears the TDS fault | fault=NONE st=STOP | st=STOP fault=NONE | PASS |
| 21 | D4: Over-pressure (>250 PSI) -> FAULT, code 4 | fault=PRESSURE fcode=4 pump=0 | st=FAULT fault=PRESSURE fcode=4 pump=0 pin=260 | PASS |
| 22 | D4c: Run/Stop=STOP clears the over-pressure fault | fault=NONE st=STOP | st=STOP fault=NONE | PASS |
| 23 | D5: Analog sensor broken wire (<3.5 mA) -> sensor FAULT, code 5 | fault=SENSOR fcode=5 pump=0 | st=FAULT fault=SENSOR fcode=5 pump=0 | PASS |
| 24 | D5c: Run/Stop=STOP clears the sensor fault | fault=NONE st=STOP | st=STOP fault=NONE | PASS |
| 25 | E1: E-stop while RUNNING -> immediate safe STOP (all outputs off, LED off) | st=STOP pump=0 sv=0 fv=0 led=OFF | st=STOP pump=0 sv=0 fv=0 led=OFF | PASS |
| 26 | E2: E-stop also clears a latched fault (STOP, fault=NONE) | st=STOP fault=NONE led=OFF | st=STOP fault=NONE led=OFF | PASS |
| 27 | F1: Minimum pump ON-time honoured (full tank does not stop pump before min-on) | pump=1 @0.8s then pump=0 @2.3s | pump@0.8s=1 pump@2.3s=0 | PASS |
| 28 | F2: Minimum pump OFF-time honoured (restart waits min-off after a stop) | pump=0 @0.8s then pump=1 @2.4s | pump@0.8s=0 pump@2.4s=1 | PASS |
| 29 | G1: Periodic flush after run interval -> FLUSHING (pump on, flush valve open, yellow solid) | st=FLUSHING pump=1 fv=1 led=YELLOW/SOLID | st=FLUSHING pump=1 fv=1 sv=1 led=YELLOW blink=SOLID | PASS |
| 30 | G2: During flush the brine-bypass (flush) valve output is energised | EQ.15=1000 EQ.14=1000 | EQ.15=1000 EQ.14=1000 | PASS |
| 31 | G3: Flush completes -> returns to RUNNING, flush valve closes | st=RUNNING fv=0 led=GREEN | st=RUNNING fv=0 led=GREEN | PASS |

## Coverage
- **A** Stopped/auto-run: power-on auto-start (no operator action), safe stop, output-cache cross-check.
- **B** Tank logic: clean-tank-full stop and supply-low pause, both with hysteresis (no short cycling at the thresholds).
- **C** Production warnings: high feed pressure, membrane-cleaning-required, low flow, recovery out of band, rising TDS - each with the correct yellow flash rate.
- **D** Faults (latched): over-temperature, dry-run, permeate TDS > 200, over-pressure, broken-wire sensor - each with its red blink code and Run/Stop reset.
- **E** Emergency stop: immediate safe state, and fault clear on STOP.
- **F** Motor anti short-cycle: minimum ON-time and minimum OFF-time.
- **G** Periodic membrane forward-flush and return to production.

## Notes
- `st` = controller state; `pump`/`sv`/`fv` = pump / supply valve / flush valve commands; `led`/`blink` = status indicator; `warn`/`fault`/`fcode` = active warning / latched fault / red blink code.
- Engineering scaling injected per spec: pressure 4-20 mA = 0-300 PSI, depth 4-20 mA = 0-500 cm, TDS-out 0-5 V = 0-1000 mg/L, motor 10K NTC, flow 100 pulses/L.
