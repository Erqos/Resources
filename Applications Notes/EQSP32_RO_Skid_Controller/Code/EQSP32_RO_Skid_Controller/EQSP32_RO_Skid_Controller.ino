/**
 * EQSP32_RO_Skid_Controller.ino
 *
 * Single-pass Reverse Osmosis (RO) skid controller for the EQSP32.
 * Implements "Reverse Osmosis Skid - Control & Operation Specification v0.3".
 *
 * I/O map (on-board EQSP32 terminals):
 *   ADIO1  CIN  Pressure IN   (4-20mA, 20mA=300 PSI)
 *   ADIO2  CIN  Pressure OUT  (4-20mA, 20mA=300 PSI)
 *   ADIO3  CIN  Depth Clean   (4-20mA, 20mA=500 cm)
 *   ADIO4  CIN  Depth Supply  (4-20mA, 20mA=500 cm)
 *   ADIO5  AIN  TDS IN        (0-5V, 5V=10000 mg/L)
 *   ADIO6  AIN  TDS OUT       (0-5V, 5V=1000 mg/L)
 *   ADIO7  DIN  Run/Stop selector (1=RUN, 0=STOP/E-stop, also clears faults)
 *   ADIO8  TIN  Motor temp    (10K NTC, default Beta 3435 / 10k)
 *   DIO9   PCC  Flow IN       (100 pulses = 1 L)
 *   DIO10  PCC  Flow OUT      (100 pulses = 1 L)
 *   DIO11  POUT RGB Red
 *   DIO12  POUT RGB Green
 *   DIO13  POUT RGB Blue
 *   DIO14  POUT Flush valve
 *   DIO15  POUT RO Pump contactor
 *   DIO16  POUT Supply valve
 *
 * TEST BUILD: with HIL_TEST defined, beginHil() is enabled (inputs injected over
 * USB serial / COM35) and the long process timers are time-compressed so the full
 * state machine can be validated in well under a minute. The control LOGIC and
 * thresholds are identical to production; only durations are scaled. See the
 * timing table below. For a production build, comment out "#define HIL_TEST".
 *
 * Observability: a structured telemetry line is emitted on every state/output
 * change and as a 1 Hz heartbeat:
 *   >>STATE st=<..> pump=<0/1> sv=<0/1> fv=<0/1> led=<COLOR> blink=<PATTERN>
 *           warn=<code> fault=<code> fcode=<n> feed=<Lpm> perm=<Lpm> rec=<%>
 *           pin=<PSI> pout=<PSI> tdso=<mg/L> temp=<C> sup=<cm> cln=<cm>
 */

#include <EQSP32.h>

#define HIL_TEST          // comment out for production build

EQSP32 eqsp32;

// ---- terminal pins ----
const int P_IN = 1, P_OUT = 2, DEPTH_CLEAN = 3, DEPTH_SUPPLY = 4;
const int TDS_IN = 5, TDS_OUT = 6, RUNSTOP = 7, MOTOR_TEMP = 8;
const int FLOW_IN = 9, FLOW_OUT = 10;
const int LED_R = 11, LED_G = 12, LED_B = 13;
const int FLUSH_V = 14, PUMP = 15, SUPPLY_V = 16;

const int ON = 1000, OFF = 0;   // POUT duty for digital on/off

// ---- process setpoints (identical in test & production) ----
const float SUPPLY_MIN = 50,  SUPPLY_RESUME = 60;     // cm
const float CLEAN_FULL = 400, CLEAN_RESTART = 380;    // cm
const float P_OP_LO = 150, P_OP_HI = 200;             // PSI operating band
const float P_OVER = 250;                             // PSI over-pressure trip
const float TDS_MAX = 200, TDS_WARN = 160;            // mg/L permeate
const float FEED_LO = 8, FEED_HI = 12;                // L/min warning band
const float REC_LO = 10, REC_HI = 30;                 // % recovery band
const float TEMP_MAX = 80;                            // deg C
const float FLOW_DRY = 0.5;                           // L/min dry-run threshold
const float FOUL_PERM = 2.0;                          // L/min "permeate low" for fouling
const int   CIN_BROKEN = 350;                         // raw (mA*100) < 3.5 mA => broken wire

// ---- timing (compressed under HIL_TEST) ----
#ifdef HIL_TEST
const uint32_t T_SETTLE = 1500, T_MIN_ON = 1500, T_MIN_OFF = 1500, T_DRYRUN = 1500;
const uint32_t T_FLUSH_IVL = 8000, T_FLUSH_DUR = 2000, T_TDS_FLT = 3000;
const uint32_t T_FAULT_DB = 600;
#else
const uint32_t T_SETTLE = 25000, T_MIN_ON = 10000, T_MIN_OFF = 10000, T_DRYRUN = 10000;
const uint32_t T_FLUSH_IVL = 3600000UL, T_FLUSH_DUR = 300000UL, T_TDS_FLT = 600000UL;
const uint32_t T_FAULT_DB = 5000;
#endif

// ---- state ----
enum SkidState { ST_STOP, ST_IDLE_FULL, ST_PAUSE_SUPPLY, ST_STARTING, ST_RUNNING, ST_FLUSHING, ST_FAULT };
const char* STATE_NAME[] = { "STOP", "IDLE_FULL", "PAUSE_SUPPLY", "STARTING", "RUNNING", "FLUSHING", "FAULT" };
enum Phase { PH_STOPPED, PH_STARTING, PH_RUNNING, PH_FLUSHING };
enum Fault { F_NONE, F_TEMP, F_DRYRUN, F_TDS, F_PRESSURE, F_SENSOR };
const char* FAULT_NAME[] = { "NONE", "TEMP", "DRYRUN", "TDS", "PRESSURE", "SENSOR" };
const int   FAULT_CODE[] = { 0, 1, 2, 3, 4, 5 };   // RED blink code
enum Warn { W_NONE, W_CLEAN, W_TDS, W_REC, W_FLOW, W_HP, W_LP };
const char* WARN_NAME[] = { "NONE", "CLEAN", "TDS", "REC", "FLOW", "HP", "LP" };
enum Color { C_OFF, C_RED, C_GREEN, C_BLUE, C_YELLOW };
const char* COLOR_NAME[] = { "OFF", "RED", "GREEN", "BLUE", "YELLOW" };
enum Pattern { P_NONE, P_SOLID, P_SLOW, P_MED, P_FAST, P_BLINK, P_CODE };
const char* PATT_NAME[] = { "NONE", "SOLID", "SLOW", "MED", "FAST", "BLINK", "CODE" };

SkidState state = ST_STOP;
Phase  phase = PH_STOPPED;
Fault  fault = F_NONE;
Warn   warn  = W_NONE;
Color  ledColor = C_OFF;
Pattern ledPatt = P_NONE;
bool   pumpOn = false, svOpen = false, fvOpen = false;

// hysteresis latches
bool fullLatch = false, lowLatch = false;

// timers
uint32_t pumpOnTime = 0, pumpOffTime = 0, settleStart = 0, flushStart = 0, runSinceFlush = 0;
uint32_t sinceSensor = 0, sinceTemp = 0, sinceOP = 0, sinceDry = 0, sinceTds = 0;
uint32_t lastFlowSample = 0, lastBeat = 0;

// measured values
float pin = 0, pout = 0, cleanCm = 0, supplyCm = 0, tdsOut = 0, tdsIn = 0, tempC = 0;
float feedLpm = 0, permLpm = 0, recovery = 0;
int rawPIn = 0, rawPOut = 0, rawClean = 0, rawSupply = 0;

// ---- scaling ----
float psiFromCIN(int raw) { return ((raw / 100.0f) - 4.0f) / 16.0f * 300.0f; }
float cmFromCIN(int raw)  { return ((raw / 100.0f) - 4.0f) / 16.0f * 500.0f; }
float tdsOutFromAIN(int mv){ return mv / 5000.0f * 1000.0f; }
float tdsInFromAIN(int mv) { return mv / 5000.0f * 10000.0f; }
float cFromTIN(int raw)    { return raw / 10.0f; }

// ---- helpers ----
void writeOutputs() {
    eqsp32.pinValue(PUMP,     pumpOn ? ON : OFF);
    eqsp32.pinValue(SUPPLY_V, svOpen ? ON : OFF);
    eqsp32.pinValue(FLUSH_V,  fvOpen ? ON : OFF);
}

void startPump() {
    pumpOn = true; svOpen = true; fvOpen = false;
    phase = PH_STARTING; settleStart = millis(); pumpOnTime = millis();
    writeOutputs();
}
void stopPump() {
    pumpOn = false; svOpen = false; fvOpen = false;
    phase = PH_STOPPED; pumpOffTime = millis();
    writeOutputs();
}
void enterStop() {                 // E-stop / run-off: safe + clears faults
    pumpOn = false; svOpen = false; fvOpen = false; phase = PH_STOPPED;
    fault = F_NONE; sinceSensor = sinceTemp = sinceOP = sinceDry = sinceTds = 0;
    pumpOffTime = millis(); state = ST_STOP;
    writeOutputs();
}
void enterFault(Fault f) {
    fault = f; pumpOn = false; svOpen = false; fvOpen = false; phase = PH_STOPPED;
    pumpOffTime = millis(); state = ST_FAULT;
    writeOutputs();
}

bool due(bool cond, uint32_t &since, uint32_t dur) {
    uint32_t now = millis();
    if (!cond) { since = 0; return false; }
    if (since == 0) since = now;
    return (now - since >= dur);
}

void sampleFlow() {
    uint32_t now = millis();
    uint32_t dt = now - lastFlowSample;
    if (dt < 1000) return;
    lastFlowSample = now;
    int pf = eqsp32.readPin(FLOW_IN);
    int pp = eqsp32.readPin(FLOW_OUT);
    if (pf < 0) pf = 0;
    if (pp < 0) pp = 0;
    feedLpm = pf * 60000.0f / dt / 100.0f;
    permLpm = pp * 60000.0f / dt / 100.0f;
    recovery = (feedLpm > 0.1f) ? (permLpm / feedLpm * 100.0f) : 0;
}

void readInputs() {
    rawPIn = eqsp32.readPin(P_IN);   pin = psiFromCIN(rawPIn);
    rawPOut = eqsp32.readPin(P_OUT); pout = psiFromCIN(rawPOut);
    rawClean = eqsp32.readPin(DEPTH_CLEAN);   cleanCm = cmFromCIN(rawClean);
    rawSupply = eqsp32.readPin(DEPTH_SUPPLY); supplyCm = cmFromCIN(rawSupply);
    tdsIn  = tdsInFromAIN(eqsp32.readPin(TDS_IN));
    tdsOut = tdsOutFromAIN(eqsp32.readPin(TDS_OUT));
    tempC  = cFromTIN(eqsp32.readPin(MOTOR_TEMP));
}

void updateHysteresis() {
    if (cleanCm >= CLEAN_FULL) fullLatch = true;
    else if (cleanCm <= CLEAN_RESTART) fullLatch = false;
    if (supplyCm < SUPPLY_MIN) lowLatch = true;
    else if (supplyCm >= SUPPLY_RESUME) lowLatch = false;
}

bool evaluateFaults() {
    bool sensorBad = (rawPIn < CIN_BROKEN) || (rawPOut < CIN_BROKEN) ||
                     (rawClean < CIN_BROKEN) || (rawSupply < CIN_BROKEN);
    if (due(sensorBad, sinceSensor, T_FAULT_DB))            { enterFault(F_SENSOR); return true; }
    if (due(tempC >= TEMP_MAX, sinceTemp, T_FAULT_DB))      { enterFault(F_TEMP);   return true; }
    if (due(pin > P_OVER || pout > P_OVER, sinceOP, T_FAULT_DB)) { enterFault(F_PRESSURE); return true; }
    bool producing = (phase == PH_RUNNING);
    if (due(producing && feedLpm < FLOW_DRY, sinceDry, T_DRYRUN)) { enterFault(F_DRYRUN); return true; }
    if (due(producing && tdsOut > TDS_MAX, sinceTds, T_TDS_FLT))  { enterFault(F_TDS);    return true; }
    return false;
}

Warn computeWarn() {
    if (pin > P_OP_HI && permLpm < FOUL_PERM) return W_CLEAN;
    if (tdsOut > TDS_WARN)                    return W_TDS;
    if (recovery < REC_LO || recovery > REC_HI) return W_REC;
    if (feedLpm < FEED_LO || feedLpm > FEED_HI) return W_FLOW;
    if (pin > P_OP_HI)                         return W_HP;
    if (pin < P_OP_LO)                         return W_LP;
    return W_NONE;
}

void deriveLed() {
    warn = W_NONE;
    switch (state) {
        case ST_STOP:         ledColor = C_OFF;    ledPatt = P_NONE;  break;
        case ST_FAULT:        ledColor = C_RED;    ledPatt = P_CODE;  break;
        case ST_FLUSHING:     ledColor = C_YELLOW; ledPatt = P_SOLID; break;
        case ST_STARTING:     ledColor = C_GREEN;  ledPatt = P_SOLID; break;
        case ST_IDLE_FULL:    ledColor = C_BLUE;   ledPatt = P_SOLID; break;
        case ST_PAUSE_SUPPLY: ledColor = C_BLUE;   ledPatt = P_BLINK; break;
        case ST_RUNNING:
            warn = computeWarn();
            switch (warn) {
                case W_CLEAN: case W_TDS: ledColor = C_YELLOW; ledPatt = P_FAST; break;
                case W_REC:   case W_FLOW:ledColor = C_YELLOW; ledPatt = P_MED;  break;
                case W_HP:    case W_LP:  ledColor = C_YELLOW; ledPatt = P_SLOW; break;
                default:                  ledColor = C_GREEN;  ledPatt = P_SOLID; break;
            }
            break;
    }
}

void driveLedPins() {
    uint32_t t = millis();
    bool on = true;
    switch (ledPatt) {
        case P_SOLID: on = true; break;
        case P_SLOW:  on = (t % 1000) < 500; break;
        case P_MED:   on = (t % 400)  < 200; break;
        case P_FAST:  on = (t % 160)  < 80;  break;
        case P_BLINK: on = (t % 600)  < 300; break;
        case P_CODE:  on = (t % 400)  < 200; break;   // generic fault flash
        default:      on = false; break;
    }
    bool r = on && (ledColor == C_RED  || ledColor == C_YELLOW);
    bool g = on && (ledColor == C_GREEN|| ledColor == C_YELLOW);
    bool b = on && (ledColor == C_BLUE);
    eqsp32.pinValue(LED_R, r ? ON : OFF);
    eqsp32.pinValue(LED_G, g ? ON : OFF);
    eqsp32.pinValue(LED_B, b ? ON : OFF);
}

String sig() {
    char buf[48];
    snprintf(buf, sizeof(buf), "%d|%d%d%d|%d%d|%d|%d", (int)state,
             pumpOn ? 1 : 0, svOpen ? 1 : 0, fvOpen ? 1 : 0,
             (int)ledColor, (int)ledPatt, (int)warn, (int)fault);
    return String(buf);
}
String lastSig = "";

void emitState(bool force) {
    uint32_t now = millis();
    String s = sig();
    if (!force && s == lastSig && (now - lastBeat) < 1000) return;
    lastSig = s; lastBeat = now;
    Serial.printf(">>STATE st=%s pump=%d sv=%d fv=%d led=%s blink=%s warn=%s fault=%s fcode=%d "
                  "feed=%.1f perm=%.1f rec=%.0f pin=%.0f pout=%.0f tdso=%.0f temp=%.0f sup=%.0f cln=%.0f\n",
                  STATE_NAME[state], pumpOn ? 1 : 0, svOpen ? 1 : 0, fvOpen ? 1 : 0,
                  COLOR_NAME[ledColor], PATT_NAME[ledPatt], WARN_NAME[warn], FAULT_NAME[fault],
                  FAULT_CODE[fault], feedLpm, permLpm, recovery, pin, pout, tdsOut, tempC,
                  supplyCm, cleanCm);
}

void setup() {
    Serial.begin(115200);
    delay(300);

#ifdef HIL_TEST
    eqsp32.beginHil();              // accept HIL input injection over USB serial
#endif
    EQSP32Configs cfg;
    cfg.disableErqosIoT = true;     // offline, self-contained
    eqsp32.begin(cfg, false);       // verbose OFF so HIL serial stays clean

    eqsp32.pinMode(P_IN, CIN);        eqsp32.pinMode(P_OUT, CIN);
    eqsp32.pinMode(DEPTH_CLEAN, CIN); eqsp32.pinMode(DEPTH_SUPPLY, CIN);
    eqsp32.pinMode(TDS_IN, AIN);      eqsp32.pinMode(TDS_OUT, AIN);
    eqsp32.pinMode(RUNSTOP, DIN);
    eqsp32.pinMode(MOTOR_TEMP, TIN);  eqsp32.configTIN(MOTOR_TEMP, 3435, 10000);
    eqsp32.pinMode(FLOW_IN, PCC);     eqsp32.configPCC(FLOW_IN, ON_RISING);
    eqsp32.pinMode(FLOW_OUT, PCC);    eqsp32.configPCC(FLOW_OUT, ON_RISING);
    for (int p = LED_R; p <= SUPPLY_V; p++) { eqsp32.pinMode(p, POUT); eqsp32.pinValue(p, OFF); }

    state = ST_STOP; pumpOffTime = millis(); lastFlowSample = millis();
    deriveLed(); emitState(true);
    Serial.println(">>READY EQSP32 RO Skid Controller (HIL build)");
}

void loop() {
    readInputs();
    sampleFlow();

    bool runOn = (eqsp32.readPin(RUNSTOP) != 0);

    if (!runOn) {
        if (state != ST_STOP) enterStop();
    } else if (fault != F_NONE) {
        state = ST_FAULT;                       // remain latched until run -> stop
    } else {
        updateHysteresis();
        if (!evaluateFaults()) {
            bool block = fullLatch || lowLatch;
            if (pumpOn) {
                bool minOnOk = (millis() - pumpOnTime >= T_MIN_ON);
                if (block && minOnOk) {
                    stopPump();
                } else {
                    if (phase == PH_STARTING) {
                        if (millis() - settleStart >= T_SETTLE) { phase = PH_RUNNING; runSinceFlush = millis(); }
                    } else if (phase == PH_RUNNING) {
                        if (millis() - runSinceFlush >= T_FLUSH_IVL) { phase = PH_FLUSHING; flushStart = millis(); fvOpen = true; writeOutputs(); }
                    } else if (phase == PH_FLUSHING) {
                        if (millis() - flushStart >= T_FLUSH_DUR) { phase = PH_RUNNING; runSinceFlush = millis(); fvOpen = false; writeOutputs(); }
                    }
                }
            } else {
                bool minOffOk = (millis() - pumpOffTime >= T_MIN_OFF);
                if (!block && minOffOk) startPump();
            }
            // derive operational state
            if (pumpOn) state = (phase == PH_FLUSHING) ? ST_FLUSHING : (phase == PH_STARTING ? ST_STARTING : ST_RUNNING);
            else        state = fullLatch ? ST_IDLE_FULL : (lowLatch ? ST_PAUSE_SUPPLY : ST_IDLE_FULL);
        }
    }

    deriveLed();
    driveLedPins();
    emitState(false);
    delay(40);
}
