
# SHA256 FPGA Accelerator

This project implements a hardware accelerator for the SHA256 cryptographic algorithm on an FPGA, integrated with a RISC-V processor using memory-mapped I/O. It offloads the computationally intensive `SHA256Transform()` function from software to hardware, achieving a **2.6× performance improvement**.

---

## 🚀 Features

- Hardware acceleration of SHA256 core compression loop
- Integrated via memory-mapped I/O with a RISC-V system
- 64-round parallel SHA256 implementation in SystemVerilog
- Synchronization using FSM and memory-mapped control/status flags
- Minimal software modification: SHA256Init, SHA256Update, SHA256Final interface unchanged
- Tested on Digilent Nexys A7-100T (Artix-7 FPGA) with SEGGER Embedded Studio

---

## 📁 Repository Structure

```
sha256-fpga-accelerator/
├── rtl/              # accelerator.sv, accelerator_regs.sv, accelerator_top.sv
├── sw/               # sha256.c (modified software interface)
├── docs/             # Diagrams, memory map, performance charts
├── synth/            # Resource + Timing Reports
└── README.md         # This file
```

---

## 💻 Running the Project

### Requirements

- Vivado 2023.2 or later
- SEGGER Embedded Studio for RISC-V
- Digilent Nexys A7-100T
- C toolchain with RISC-V support

---

## 📊 Performance

- **Cycles to hash 20 strings:** 817,193
- **Average per hash:** ~40,860 cycles
- **Speedup vs software:** 2.6×
- **Correctness:** Matched software output on all test cases

---

## 📐 Design Details

- **accelerator.sv:** SHA256Transform rounds, message scheduler, compression logic
- **accelerator_regs.sv:** Memory-mapped interface with control and data registers
- **accelerator_top.sv:** Integration and control FSM
- **sha256.c:** Modified software SHA256 function to use hardware acceleration
- Note: accelerator_wb.sv is provided by the hackathon; rest of the RTL (accelerator.sv, accelerator_regs.sv, top-level FSM) was modified by us.
