### **EQSP32 OpenPLC package 1.0.0 release**

---

> _**Requires OpenPLC Editor 4.3.0 or newer** (tested with 4.3.2). The EQSP32 library v1.6.0 is included.  
> **Update your EQConnect App to version 2.1.0 (revision 2026 1015) or later** to see pin names in EQMonitor.  
> Go to [Erqos resources utilities](https://erqos.com/resources/#Utilities)._

---

> **Opening a project made with package 0.7.x:**
> - **Set up Modbus again.** OpenPLC Editor 4.3 keeps Modbus in the project's Modbus server (Servers) and does not take over the old Modbus settings. Add a Modbus server, and fill in the **Network** screen for Modbus TCP.
> - **PT100 (EQXPT) values are now °C × 10**, like TIN and TC. Before, they were °C × 100. Change any scaling in the program.
> - **Temperature faults read −32768** (open or shorted TIN sensor, TC and PT sensor faults, a temperature module that does not answer). Before, TIN read ±9999 and TC/PT faults looked like temperatures.
> - **A missing expansion module reads FALSE / 0**, never TRUE. Make FALSE the safe state of every input that permits motion or heat.

---


**New Features |** EQSP32 library included
- The package contains the EQSP32 library v1.6.0. Every project builds with it, whatever EQSP32 library is installed on the PC


**New Features |** Quadrature encoder (QENC)
- Set DIO9, 11, 13 or 15 to *QENC A (Quad encoder signal A)* and the next terminal to *QENC B (Quad encoder signal B)*
- QENC A gives the position as a 32-bit `DINT`; QENC B is TRUE while the position counts up
- Signal format in Configuration: A/B ×4, ×2 or ×1, pulse + direction, or up/down pulses; the counting direction can be reversed


**New Features |** Pulse counting (PCC)
- New mode *PCC (Pulse Total)*: a 32-bit running total (`DINT`) that reading never clears
- *Pulse Edge* also offers *Both edges*


**New Features |** Pin names
- The alias you give a terminal or a module channel in the System Layout is shown as its name in EQMonitor


**New Features |** EQXHI module
- 10 isolated AC/DC voltage-presence inputs
- Optional per module: the measured frequency (Hz × 10) and the frequency quality of each input; frequency monitoring per COM group


**New Features |** Modbus
- Modbus RTU on RS485 or RS232: in the project's Modbus server pick `RS485_Port` or `RS232_Port`; set the parity on the **Serial** screen
- Modbus TCP over Ethernet and Wi-Fi, set on the **Network** screen
- The Modbus register map is in the user manual (§10)


**New Features |** Network and EQConnect options
- *Keep Ethernet and Wi-Fi both on*: for example Modbus on a fixed Ethernet address and Wi-Fi with DHCP for EQConnect
- *Disable Erqos IoT*: no BLE, EQConnect or EQMonitor; the EQSP32 works on Ethernet only
- *BLE advertising time*: how long the EQSP32 stays visible to EQConnect and EQMonitor after it starts (0 = always)


**New Features |** Relay Sequencer
- Slot 0 Configuration: RELAY outputs switched on together pull in one after another


**New Features |** Debugger
- The debugger always works over USB, without any Modbus settings
- With the network on, the debugger also works over the network


---

**Examples |** New: one per language, in the kit's `examples/` folder
- *EQSP32_Conveyor* (ST): start and stop buttons, the belt position from an encoder and a home switch, a part counter, and the values ready for an HMI over Modbus
- *EQSP32_Start_Stop* (Ladder): start/stop with a set coil and a reset coil, and a run lamp
- *EQSP32_Fan_Timer* (FBD): a fan with an on-delay and an off-delay timer
- *EQSP32_Guard_Interlock* (IL): a motor interlocked with a guard switch, and a warning lamp

---

**Optimizations |** OpenPLC Editor 4.3
- Works with OpenPLC Editor 4.3.0 or newer
- Default aliases use `_` (`ADIO_3`, `XIO_1_DIO3`), because the editor does not accept `.` in an alias

**Optimizations |** Installation
- Builds work with any Windows user name: the trust patch moves OpenPLC's Arduino folder to `C:\EQSP32-OpenPLC`

**Optimizations |** Build messages
- A wrong set-up stops the build with a clear message: an incomplete encoder pair, or more than four pulse counters and encoders on DIO9-16
- Every package message starts with `EQSP32:`, so a search of the console finds it

**Optimizations |** Counters
- Pulse totals and encoder positions roll over as normal 32-bit counters: `Now - Start` stays right across a roll-over

---

**Fixes |** Modbus
- Modbus works with OpenPLC Editor 4.3, which moved the Modbus settings to **Servers → Modbus server**. The EQSP32's ports are set on the **Network** and **Serial** screens

**Fixes |** Debugger
- The debugger connects without Modbus settings; before, the editor refused to connect unless Modbus was enabled

**Fixes |** EQXRA
- Analog outputs in *SAOUT* now change, and AO1 and AO2 move together

**Fixes |** Pulse counting
- More than four pulse counters and encoders now stop the build with a message; before, the fifth was not counted

---

**Notes**
- **Run the trust patch again after every OpenPLC Editor update** (see INSTALL).

- **Power the EQSP32 through VIn when an encoder is connected.**

- **Modbus masters:** set the timeout to at least 2 s; on RS485, wait at least 10 ms between a reply and the next request.

- **Static IP address:** with Erqos IoT on, the address set on the Network screen is applied by a network reset: hold BOOT for 3 s (this also clears the Wi-Fi network). Otherwise set the address with the EQConnect app.

- On the first build OpenPLC downloads the ESP32 Arduino Core v2.0.17 and RadioLib 7.7.1 by itself.

- On the first upload, Windows Firewall may ask about `mdns-discovery`; denying it is fine for uploads over USB.

- Tested on Windows.
