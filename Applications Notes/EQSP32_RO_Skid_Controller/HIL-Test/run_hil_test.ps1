# =====================================================================
# HIL validation harness for EQSP32_RO_Skid_Controller
#
# Drives every sensor of the RO skid over the EQSP32 HIL serial protocol
# (COM35), reads back the controller's outputs and structured >>STATE
# telemetry, and checks the control behaviour against the RO Skid Control
# & Operation Specification v0.3. Produces TEST_REPORT.md.
#
# Injection model: PCC (flow) inputs are consumed on read, so the ENTIRE
# input vector is (re)applied as a single periodic HIL frame ("-!#300/...")
# every time any input changes. This keeps the flow meters continuously
# fed while sticky analog/digital values are simply repeated.
#
# HIL test build uses time-compressed process timers (see firmware):
#   settle 1.5s, min-on 1.5s, min-off 1.5s, dry-run grace 1.5s,
#   flush interval 8s, flush 2s, TDS-trip 3s, fault debounce 0.6s.
# =====================================================================

$ErrorActionPreference = 'Stop'
$PortName = 'COM35'
$Baud = 115200
$ReportPath = Join-Path $PSScriptRoot 'TEST_REPORT.md'

$script:results = New-Object System.Collections.ArrayList
$script:latest  = @{}

# ---- serial ----
$port = New-Object System.IO.Ports.SerialPort($PortName, $Baud, 'None', 8, 'One')
$port.ReadTimeout = 200
$port.NewLine = "`n"
$port.DtrEnable = $true
$port.RtsEnable = $true   # opening the port auto-resets the EQSP32

function UpdateLatest([string]$line) {
    if ($line -like '>>STATE*') {
        foreach ($m in [regex]::Matches($line, '(\w+)=(-?[\d.]+|\w+)')) {
            $script:latest[$m.Groups[1].Value] = $m.Groups[2].Value
        }
    }
}
function ReadFor([int]$ms) {
    $end = (Get-Date).AddMilliseconds($ms)
    while ((Get-Date) -lt $end) { try { UpdateLatest $port.ReadLine() } catch [TimeoutException] {} }
}
function ReadUntil([datetime]$t) {
    while ((Get-Date) -lt $t) { try { UpdateLatest $port.ReadLine() } catch [TimeoutException] {} }
}
function WaitFor([scriptblock]$cond, [int]$timeout) {
    $end = (Get-Date).AddMilliseconds($timeout)
    while ((Get-Date) -lt $end) {
        try { UpdateLatest $port.ReadLine() } catch [TimeoutException] {}
        if (& $cond) { return $true }
    }
    return (& $cond)
}
function WaitReady([int]$ms) {
    $end = (Get-Date).AddMilliseconds($ms)
    while ((Get-Date) -lt $end) { try { if ($port.ReadLine() -like '*READY*') { return $true } } catch [TimeoutException] {} }
    return $false
}

# ---- injection (raw HIL units) ----
function Healthy {
    return @{ 1 = 1333; 2 = 1280; 3 = 1040; 4 = 1360; 5 = 200; 6 = 200; 7 = 0; 8 = 250; 9 = 17; 10 = 3 }
}
$script:inj = Healthy
function Apply {
    $parts = $script:inj.Keys | Sort-Object | ForEach-Object { "EQ.$_=$($script:inj[$_])" }
    $port.WriteLine("-!#300/" + ($parts -join "/"))
    ReadFor 150
}
function SetP($k, $v) { $script:inj[$k] = $v; Apply }
function SetMany([hashtable]$h) { foreach ($k in $h.Keys) { $script:inj[$k] = $h[$k] }; Apply }

function ResetRunning {
    $script:inj = Healthy
    Apply
    [void](WaitFor { $script:latest.st -eq 'STOP' } 4000)
    $script:inj[7] = 1; Apply
    [void](WaitFor { $script:latest.st -eq 'RUNNING' } 7000)
}
function ResetStopped {
    $script:inj = Healthy
    Apply
    [void](WaitFor { $script:latest.st -eq 'STOP' } 4000)
}
function ClearFault {
    $script:inj[7] = 0; Apply
    [void](WaitFor { $script:latest.st -eq 'STOP' } 4000)
}
function QueryPin($pin) {
    for ($a = 0; $a -lt 3; $a++) {
        $port.WriteLine("-?EQ.$pin")
        $end = (Get-Date).AddMilliseconds(600)
        while ((Get-Date) -lt $end) {
            try {
                $l = $port.ReadLine(); UpdateLatest $l
                $m = [regex]::Match($l, "EQ\.$pin=(-?\d+)")
                if ($m.Success) { return [int]$m.Groups[1].Value }
            } catch [TimeoutException] {}
        }
    }
    return -999
}

# ---- assertion ----
function Snap([string[]]$fields) { return ($fields | ForEach-Object { "$_=" + $script:latest[$_] }) -join ' ' }
function Record($tc, $desc, $pass, $exp, $act) {
    [void]$script:results.Add([pscustomobject]@{ TC = $tc; Desc = $desc; Expected = $exp; Actual = $act; Pass = $pass })
    $tag = if ($pass) { 'PASS' } else { 'FAIL' }
    Write-Output ("[{0}] {1} | {2}" -f $tag, $tc, $desc)
}
function Check($tc, $desc, [scriptblock]$cond, $exp, [string[]]$show, [int]$timeout = 4000) {
    $ok = WaitFor $cond $timeout
    Record $tc $desc $ok $exp (Snap $show)
}

# =====================================================================
$port.Open()
if (-not (WaitReady 8000)) { Write-Output "WARNING: did not see >>READY banner" }
ReadFor 300
Write-Output "Connected to $PortName. Running RO skid HIL validation...`n"

# ---------- A. Stopped & auto-run ----------
ResetStopped
Check "A1" "Run/Stop=STOP with healthy sensors -> safe STOP, LED off" `
    { $script:latest.st -eq 'STOP' -and $script:latest.pump -eq '0' -and $script:latest.sv -eq '0' -and $script:latest.fv -eq '0' -and $script:latest.led -eq 'OFF' } `
    "st=STOP pump=0 sv=0 fv=0 led=OFF" @('st', 'pump', 'sv', 'fv', 'led')

$script:inj[7] = 1; Apply
Check "A2" "Run/Stop=RUN -> auto-start through STARTING to RUNNING (no operator start)" `
    { $script:latest.st -eq 'RUNNING' -and $script:latest.pump -eq '1' -and $script:latest.sv -eq '1' -and $script:latest.fv -eq '0' -and $script:latest.led -eq 'GREEN' } `
    "st=RUNNING pump=1 sv=1 fv=0 led=GREEN" @('st', 'pump', 'sv', 'fv', 'led') 7000

$qp = QueryPin 15; $qs = QueryPin 16; $qf = QueryPin 14
Record "A3" "Output cache cross-check (pump/supply/flush POUT duty)" `
    (($qp -eq 1000) -and ($qs -eq 1000) -and ($qf -eq 0)) `
    "EQ.15=1000 EQ.16=1000 EQ.14=0" "EQ.15=$qp EQ.16=$qs EQ.14=$qf"

# ---------- B. Tank levels & hysteresis ----------
SetP 3 1696   # clean 405 cm -> full
Check "B1" "Clean tank full (>=400) -> stop, IDLE_FULL, blue solid" `
    { $script:latest.st -eq 'IDLE_FULL' -and $script:latest.pump -eq '0' -and $script:latest.led -eq 'BLUE' -and $script:latest.blink -eq 'SOLID' } `
    "st=IDLE_FULL pump=0 led=BLUE/SOLID" @('st', 'pump', 'led', 'blink') 5000

SetP 3 1632   # clean 385 cm -> still latched full (>380)
ReadFor 1500
Record "B2" "Clean 385 (between 380-400) -> hysteresis holds, stays stopped" `
    ($script:latest.st -eq 'IDLE_FULL' -and $script:latest.pump -eq '0') `
    "st=IDLE_FULL pump=0" (Snap @('st', 'pump', 'cln'))

SetP 3 1600   # clean 375 cm -> restart
Check "B3" "Clean falls to 375 (<=380) -> auto restart to RUNNING" `
    { $script:latest.st -eq 'RUNNING' -and $script:latest.pump -eq '1' } `
    "st=RUNNING pump=1" @('st', 'pump', 'cln') 6000

SetP 4 528    # supply 40 cm -> low
Check "B4" "Supply tank low (<50) -> pause, PAUSE_SUPPLY, blue blink" `
    { $script:latest.st -eq 'PAUSE_SUPPLY' -and $script:latest.pump -eq '0' -and $script:latest.led -eq 'BLUE' -and $script:latest.blink -eq 'BLINK' } `
    "st=PAUSE_SUPPLY pump=0 led=BLUE/BLINK" @('st', 'pump', 'led', 'blink') 5000

SetP 4 576    # supply 55 cm -> still latched low (<60)
ReadFor 1500
Record "B5" "Supply 55 (between 50-60) -> hysteresis holds, stays paused" `
    ($script:latest.st -eq 'PAUSE_SUPPLY' -and $script:latest.pump -eq '0') `
    "st=PAUSE_SUPPLY pump=0" (Snap @('st', 'pump', 'sup'))

SetP 4 608    # supply 65 cm -> resume
Check "B6" "Supply rises to 65 (>=60) -> auto resume to RUNNING" `
    { $script:latest.st -eq 'RUNNING' -and $script:latest.pump -eq '1' } `
    "st=RUNNING pump=1" @('st', 'pump', 'sup') 6000

# ---------- C. Production warnings (yellow flash codes) ----------
ResetRunning; SetMany @{ 1 = 1520; 10 = 4 }   # pin 210 PSI, permeate 2.4 L/min (>foul)
Check "C1" "Feed pressure >200 with normal flow -> early-fouling WARNING (yellow slow)" `
    { $script:latest.st -eq 'RUNNING' -and $script:latest.warn -eq 'HP' -and $script:latest.led -eq 'YELLOW' -and $script:latest.blink -eq 'SLOW' } `
    "warn=HP led=YELLOW/SLOW" @('warn', 'led', 'blink', 'pin') 4000

ResetRunning; SetMany @{ 1 = 1520; 10 = 1 }   # pin 210 PSI, permeate 0.6 L/min (low)
Check "C2" "Feed pressure >200 with low permeate -> CLEANING REQUIRED (yellow fast)" `
    { $script:latest.warn -eq 'CLEAN' -and $script:latest.led -eq 'YELLOW' -and $script:latest.blink -eq 'FAST' } `
    "warn=CLEAN led=YELLOW/FAST" @('warn', 'led', 'blink', 'pin', 'perm') 4000

ResetRunning; SetMany @{ 9 = 8; 10 = 1 }      # feed 4.8 L/min (<8), recovery in band
Check "C3" "Low feed flow (<8 L/min) -> flow WARNING (yellow medium)" `
    { $script:latest.warn -eq 'FLOW' -and $script:latest.led -eq 'YELLOW' -and $script:latest.blink -eq 'MED' } `
    "warn=FLOW led=YELLOW/MED" @('warn', 'led', 'blink', 'feed') 4000

ResetRunning; SetMany @{ 9 = 17; 10 = 6 }     # feed 10.2, permeate 3.6 -> recovery 35% (>30)
Check "C4" "Recovery out of band (>30%) -> recovery WARNING (yellow medium)" `
    { $script:latest.warn -eq 'REC' -and $script:latest.led -eq 'YELLOW' -and $script:latest.blink -eq 'MED' } `
    "warn=REC led=YELLOW/MED" @('warn', 'led', 'blink', 'rec') 4000

ResetRunning; SetP 6 900                       # TDS OUT 180 mg/L (rising, <200)
Check "C5" "Rising permeate TDS (>160, <200) -> TDS WARNING (yellow fast)" `
    { $script:latest.warn -eq 'TDS' -and $script:latest.led -eq 'YELLOW' -and $script:latest.blink -eq 'FAST' } `
    "warn=TDS led=YELLOW/FAST" @('warn', 'led', 'blink', 'tdso') 4000

# ---------- D. Faults (latched; cleared by Run/Stop -> STOP) ----------
ResetRunning; SetP 8 850                        # motor 85 C
Check "D1" "Motor over-temperature (>=80C) -> FAULT, red, pump off" `
    { $script:latest.st -eq 'FAULT' -and $script:latest.fault -eq 'TEMP' -and $script:latest.fcode -eq '1' -and $script:latest.pump -eq '0' -and $script:latest.led -eq 'RED' } `
    "fault=TEMP fcode=1 pump=0 led=RED" @('st', 'fault', 'fcode', 'pump', 'led') 4000
ClearFault
Record "D1c" "Run/Stop=STOP clears the over-temperature fault" `
    ($script:latest.fault -eq 'NONE' -and $script:latest.st -eq 'STOP') "fault=NONE st=STOP" (Snap @('st', 'fault'))

ResetRunning; SetP 9 0                           # feed flow 0 while running
Check "D2" "Dry-run / no feed flow (>grace) -> FAULT, code 2" `
    { $script:latest.st -eq 'FAULT' -and $script:latest.fault -eq 'DRYRUN' -and $script:latest.fcode -eq '2' -and $script:latest.pump -eq '0' } `
    "fault=DRYRUN fcode=2 pump=0" @('st', 'fault', 'fcode', 'pump') 6000
ClearFault
Record "D2c" "Run/Stop=STOP clears the dry-run fault" `
    ($script:latest.fault -eq 'NONE' -and $script:latest.st -eq 'STOP') "fault=NONE st=STOP" (Snap @('st', 'fault'))

ResetRunning; SetP 6 1050                         # permeate TDS 210 mg/L sustained
Check "D3" "Permeate TDS >200 sustained (>=10 min, test 3s) -> FAULT, code 3" `
    { $script:latest.st -eq 'FAULT' -and $script:latest.fault -eq 'TDS' -and $script:latest.fcode -eq '3' -and $script:latest.pump -eq '0' } `
    "fault=TDS fcode=3 pump=0" @('st', 'fault', 'fcode', 'pump', 'tdso') 7000
ClearFault
Record "D3c" "Run/Stop=STOP clears the TDS fault" `
    ($script:latest.fault -eq 'NONE' -and $script:latest.st -eq 'STOP') "fault=NONE st=STOP" (Snap @('st', 'fault'))

ResetRunning; SetP 1 1787                          # pressure IN 260 PSI (>250)
Check "D4" "Over-pressure (>250 PSI) -> FAULT, code 4" `
    { $script:latest.st -eq 'FAULT' -and $script:latest.fault -eq 'PRESSURE' -and $script:latest.fcode -eq '4' -and $script:latest.pump -eq '0' } `
    "fault=PRESSURE fcode=4 pump=0" @('st', 'fault', 'fcode', 'pump', 'pin') 4000
ClearFault
Record "D4c" "Run/Stop=STOP clears the over-pressure fault" `
    ($script:latest.fault -eq 'NONE' -and $script:latest.st -eq 'STOP') "fault=NONE st=STOP" (Snap @('st', 'fault'))

ResetRunning; SetP 1 300                            # pressure IN sensor 3.0 mA (broken wire)
Check "D5" "Analog sensor broken wire (<3.5 mA) -> sensor FAULT, code 5" `
    { $script:latest.st -eq 'FAULT' -and $script:latest.fault -eq 'SENSOR' -and $script:latest.fcode -eq '5' -and $script:latest.pump -eq '0' } `
    "fault=SENSOR fcode=5 pump=0" @('st', 'fault', 'fcode', 'pump') 4000
ClearFault
Record "D5c" "Run/Stop=STOP clears the sensor fault" `
    ($script:latest.fault -eq 'NONE' -and $script:latest.st -eq 'STOP') "fault=NONE st=STOP" (Snap @('st', 'fault'))

# ---------- E. Emergency stop ----------
ResetRunning
$script:inj[7] = 0; Apply
Check "E1" "E-stop while RUNNING -> immediate safe STOP (all outputs off, LED off)" `
    { $script:latest.st -eq 'STOP' -and $script:latest.pump -eq '0' -and $script:latest.sv -eq '0' -and $script:latest.fv -eq '0' -and $script:latest.led -eq 'OFF' } `
    "st=STOP pump=0 sv=0 fv=0 led=OFF" @('st', 'pump', 'sv', 'fv', 'led') 4000

ResetRunning; SetP 1 1787
[void](WaitFor { $script:latest.st -eq 'FAULT' } 4000)
$script:inj[7] = 0; Apply
Check "E2" "E-stop also clears a latched fault (STOP, fault=NONE)" `
    { $script:latest.st -eq 'STOP' -and $script:latest.fault -eq 'NONE' -and $script:latest.led -eq 'OFF' } `
    "st=STOP fault=NONE led=OFF" @('st', 'fault', 'led') 4000

# ---------- F. Motor anti short-cycle (min ON / min OFF) ----------
ResetStopped
ReadFor 1700                           # let min-off elapse so the start is not delayed
$script:inj[7] = 1; Apply              # request run
[void](WaitFor { $script:latest.pump -eq '1' } 4000)
$tStart = Get-Date                     # pump just started
$script:inj[3] = 1696; Apply           # clean tank full immediately after start
ReadUntil $tStart.AddMilliseconds(800)
$pumpEarly = $script:latest.pump       # min-on (1.5s) not yet elapsed -> still running
ReadUntil $tStart.AddMilliseconds(2300)
$pumpLate = $script:latest.pump        # after min-on -> stopped
Record "F1" "Minimum pump ON-time honoured (full tank does not stop pump before min-on)" `
    (($pumpEarly -eq '1') -and ($pumpLate -eq '0')) `
    "pump=1 @0.8s then pump=0 @2.3s" "pump@0.8s=$pumpEarly pump@2.3s=$pumpLate"

# min-off: from a fresh stop, demand to run but pump must wait min-off
$script:inj = Healthy; Apply
[void](WaitFor { $script:latest.st -eq 'STOP' } 4000)
$tStop = Get-Date
$script:inj[7] = 1; Apply
ReadUntil $tStop.AddMilliseconds(800)
$pumpOffEarly = $script:latest.pump    # min-off (1.5s) not elapsed -> still off
ReadUntil $tStop.AddMilliseconds(2400)
$pumpOffLate = $script:latest.pump     # after min-off -> running
Record "F2" "Minimum pump OFF-time honoured (restart waits min-off after a stop)" `
    (($pumpOffEarly -eq '0') -and ($pumpOffLate -eq '1')) `
    "pump=0 @0.8s then pump=1 @2.4s" "pump@0.8s=$pumpOffEarly pump@2.4s=$pumpOffLate"

# ---------- G. Periodic membrane flush ----------
ResetRunning
Check "G1" "Periodic flush after run interval -> FLUSHING (pump on, flush valve open, yellow solid)" `
    { $script:latest.st -eq 'FLUSHING' -and $script:latest.pump -eq '1' -and $script:latest.fv -eq '1' -and $script:latest.sv -eq '1' -and $script:latest.led -eq 'YELLOW' -and $script:latest.blink -eq 'SOLID' } `
    "st=FLUSHING pump=1 fv=1 led=YELLOW/SOLID" @('st', 'pump', 'fv', 'sv', 'led', 'blink') 11000
$fpump = QueryPin 15; $fflush = QueryPin 14
Record "G2" "During flush the brine-bypass (flush) valve output is energised" `
    (($fpump -eq 1000) -and ($fflush -eq 1000)) "EQ.15=1000 EQ.14=1000" "EQ.15=$fpump EQ.14=$fflush"
Check "G3" "Flush completes -> returns to RUNNING, flush valve closes" `
    { $script:latest.st -eq 'RUNNING' -and $script:latest.fv -eq '0' -and $script:latest.led -eq 'GREEN' } `
    "st=RUNNING fv=0 led=GREEN" @('st', 'fv', 'led') 5000

# leave device safe/quiet
$script:inj = Healthy; Apply
[void](WaitFor { $script:latest.st -eq 'STOP' } 3000)
$port.Close(); $port.Dispose()

# =====================================================================
$total = $script:results.Count
$passed = ($script:results | Where-Object { $_.Pass }).Count
$failed = $total - $passed

$L = @()
$L += "# EQSP32 Reverse Osmosis Skid - HIL Test Report"
$L += ""
$L += "- **Date:** " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
$L += "- **Device:** EQSP32 (ESP32-S3) on $PortName, firmware ``EQSP32_RO_Skid_Controller`` (HIL build)"
$L += "- **Specification:** Reverse Osmosis Skid - Control & Operation Specification v0.3"
$L += "- **Method:** All sensors injected and all outputs read back over the EQSP32 HIL serial protocol; controller state, LED indication and outputs verified from ``>>STATE`` telemetry and output-cache queries."
$L += "- **Note:** Long process timers are time-compressed in the HIL build (flush interval 8 s, flush 2 s, TDS-trip 3 s, settle/min-on/min-off/dry-run grace 1.5 s). Control logic and setpoints are identical to production."
$L += ""
$L += "## Result: $passed / $total checks passed" + $(if ($failed -eq 0) { "  (ALL PASS)" } else { "  ($failed FAILED)" })
$L += ""
$L += "| # | Test | Expected | Actual | Result |"
$L += "|---|------|----------|--------|--------|"
$i = 0
foreach ($r in $script:results) {
    $i++
    $res = if ($r.Pass) { 'PASS' } else { '**FAIL**' }
    $L += "| $i | $($r.TC): $($r.Desc) | $($r.Expected) | $($r.Actual) | $res |"
}
$L += ""
$L += "## Coverage"
$L += "- **A** Stopped/auto-run: power-on auto-start (no operator action), safe stop, output-cache cross-check."
$L += "- **B** Tank logic: clean-tank-full stop and supply-low pause, both with hysteresis (no short cycling at the thresholds)."
$L += "- **C** Production warnings: high feed pressure, membrane-cleaning-required, low flow, recovery out of band, rising TDS - each with the correct yellow flash rate."
$L += "- **D** Faults (latched): over-temperature, dry-run, permeate TDS > 200, over-pressure, broken-wire sensor - each with its red blink code and Run/Stop reset."
$L += "- **E** Emergency stop: immediate safe state, and fault clear on STOP."
$L += "- **F** Motor anti short-cycle: minimum ON-time and minimum OFF-time."
$L += "- **G** Periodic membrane forward-flush and return to production."
$L += ""
$L += "## Notes"
$L += "- ``st`` = controller state; ``pump``/``sv``/``fv`` = pump / supply valve / flush valve commands; ``led``/``blink`` = status indicator; ``warn``/``fault``/``fcode`` = active warning / latched fault / red blink code."
$L += "- Engineering scaling injected per spec: pressure 4-20 mA = 0-300 PSI, depth 4-20 mA = 0-500 cm, TDS-out 0-5 V = 0-1000 mg/L, motor 10K NTC, flow 100 pulses/L."

$L -join "`r`n" | Out-File -FilePath $ReportPath -Encoding utf8

Write-Output ""
Write-Output "==================================================="
Write-Output "RESULT: $passed / $total passed, $failed failed"
Write-Output "Report: $ReportPath"
Write-Output "==================================================="
if ($failed -gt 0) { exit 1 } else { exit 0 }
