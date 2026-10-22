# EQSP32 OpenPLC package

Board package that adds the Erqos **EQSP32** to **OpenPLC Editor**, so you can
program it in IEC 61131-3: Structured Text, Ladder, FBD and Instruction List.

## Download

**Latest: [EQSP32-OpenPLC-Customer-Kit-1.0.0.zip](EQSP32-OpenPLC-Customer-Kit-1.0.0.zip)**
(package 1.0.0, EQSP32 library v1.6.0 included)

What is new in this version: [release notes](RELEASE_NOTES.md)

## Requirements

- OpenPLC Editor 4.3.0 or newer (tested with 4.3.2), on Windows
- Node.js, once, for the editor trust patch
- EQConnect App 2.1.0 or later, to see pin names in EQMonitor
  ([Erqos resources, utilities](https://erqos.com/resources/#Utilities))

## Install

1. Extract the ZIP.
2. Follow `INSTALL.md` in the kit: start OpenPLC Editor once and close it, run
   the trust patch, then add the `.vpp` file in the editor's Package Manager.
3. Open `USER_MANUAL.html` in a browser for the full guide. `RELEASE_NOTES.md`
   lists what is new.

## What is in the kit

- The signed board package (`.vpp`), `INSTALL.md`, `USER_MANUAL.html`,
  `RELEASE_NOTES.md` and `LICENSE.md`
- `examples/`: one example project per language (ST, Ladder, FBD, IL)
- `tools/`: the editor trust patch and the project migration tool
- `keys/`: the public signing key

## Projects made with 0.7.x

Before you open a project made with package 0.7.x in 1.0.0, read the
[release notes](RELEASE_NOTES.md): Modbus must be set up again, and PT100
values are now °C × 10.

## Previous versions

Only for an existing installation that must stay on an OpenPLC Editor older
than 4.3. For new work, use the latest version above.

- [0.7.3](previous/EQSP32-OpenPLC-Customer-Kit-0.7.3.zip)
