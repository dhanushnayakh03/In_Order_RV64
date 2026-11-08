#!/usr/bin/env python3
# ============================================================================
# File: run_fpga.py
# Description: Run a program on the 7-stage in-order RV64 core on PYNQ-Z2 and
#              report execution stats, architectural registers and memory.
#
# Copy to the board (same directory):
#   rv64_core.bit, rv64_core.hwh   (from the Vivado block design, same basename)
#   run_fpga.py
#   program.bin or program.mem     (from `make fpga_mem SOURCE=file.s`)
#
# Usage (on the board, as root / sudo):
#   python3 run_fpga.py program.bin
#   python3 run_fpga.py program.mem --mem-start 0x1000 --mem-count 16
#   python3 run_fpga.py program.bin --mem-all          # all non-zero doublewords
#   python3 run_fpga.py program.bin --bit my.bit --clock 50
#
# Register map: see src/rv64_pynq_top.v
# ============================================================================

import argparse
import os
import struct
import sys
import time

try:
    from pynq import Overlay, Clocks
except ImportError:
    Overlay = None
    Clocks = None

# ---------------------------------------------------------------------------
# Register map (byte offsets inside the IP's AXI window)
# ---------------------------------------------------------------------------
MEM_BYTES    = 65536      # must match MEM_SIZE_BYTES in rv64_pynq_top.v (IMEM / DMEM each)
REG_CTRL     = 0x10000    # [0] core reset (1 = hold)
REG_STATUS   = 0x10004    # [0] halted, [1] error
REG_CYCLES   = 0x10008
REG_RETIRED  = 0x1000C
REG_ERRPC_LO = 0x10010
REG_ERRPC_HI = 0x10014
REG_XREG     = 0x10100    # x[i] at REG_XREG + 8*i (lo), +4 (hi)

ABI_NAMES = ["zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
             "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
             "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7",
             "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6"]


class RV64InOrderFPGA:
    def __init__(self, bitstream="rv64_core.bit", clock_mhz=None):
        if Overlay is None:
            raise RuntimeError("pynq library not found: run this script on the PYNQ board.")
        if not os.path.exists(bitstream):
            raise FileNotFoundError(f"Bitstream '{bitstream}' not found.")
        hwh = os.path.splitext(bitstream)[0] + ".hwh"
        if not os.path.exists(hwh):
            raise FileNotFoundError(f"'{hwh}' not found: the .hwh must sit next to the .bit with the same basename.")

        print(f"[PYNQ] Loading bitstream: {bitstream}")
        self.ol = Overlay(bitstream)

        if Clocks is not None:
            if clock_mhz is not None:
                Clocks.fclk0_mhz = clock_mhz
            print(f"[PYNQ] FCLK0 (core clock): {Clocks.fclk0_mhz:.2f} MHz")

        if hasattr(self.ol, "rv64_pynq_top_0"):
            self.ip = self.ol.rv64_pynq_top_0
            name = "rv64_pynq_top_0"
        else:
            names = [k for k in self.ol.ip_dict if "rv64" in k.lower()]
            if not names:
                raise RuntimeError(f"RV64 IP not found. IPs in overlay: {list(self.ol.ip_dict)}")
            name = names[0]
            self.ip = getattr(self.ol, name)
        print(f"[PYNQ] Connected to IP: {name}")

    # --- control / status ---------------------------------------------------
    def hold_reset(self):
        self.ip.write(REG_CTRL, 1)

    def release_reset(self):
        self.ip.write(REG_CTRL, 0)

    def status(self):
        s = self.ip.read(REG_STATUS)
        return bool(s & 1), bool(s & 2)          # (halted, error)

    def read64(self, offset):
        lo = self.ip.read(offset)
        hi = self.ip.read(offset + 4)
        return (hi << 32) | lo

    # --- memory -------------------------------------------------------------
    def write_word(self, addr, val32):
        self.ip.write(addr % MEM_BYTES, val32 & 0xFFFFFFFF)

    def read_dword(self, addr):
        return self.read64(addr % MEM_BYTES)

    def clear_memory(self):
        for a in range(0, MEM_BYTES, 4):
            self.write_word(a, 0)

    def load_program(self, path):
        """Load a raw .bin (objcopy) or a .mem (make_hex.py, one 64-bit hex word per line)."""
        if path.endswith(".mem"):
            image = bytearray()
            with open(path) as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith("//") and not line.startswith("@"):
                        image += int(line, 16).to_bytes(8, "little")
            image = bytes(image).rstrip(b"\x00")   # drop padding
        else:
            with open(path, "rb") as f:
                image = f.read()

        if len(image) > MEM_BYTES:
            raise ValueError(f"Program is {len(image)} bytes, memory is only {MEM_BYTES} bytes.")
        image += b"\x00" * (-len(image) % 4)

        # Host writes land in both IMEM and DMEM (see rv64_pynq_top.v)
        self.hold_reset()
        print(f"[PYNQ] Clearing {MEM_BYTES // 1024} KB memory ...")
        self.clear_memory()
        print(f"[PYNQ] Writing {len(image)} bytes of '{path}' at 0x0000 ...")
        for i in range(0, len(image), 4):
            self.write_word(i, struct.unpack_from("<I", image, i)[0])

    # --- run ----------------------------------------------------------------
    def run(self, timeout_sec=5.0):
        print("[PYNQ] Releasing reset -> core running ...")
        t0 = time.time()
        self.release_reset()
        while True:
            halted, error = self.status()
            if halted:
                return True, error
            if time.time() - t0 > timeout_sec:
                return False, False

    # --- reporting ----------------------------------------------------------
    def print_stats(self, halted, error):
        cycles  = self.ip.read(REG_CYCLES)
        retired = self.ip.read(REG_RETIRED)
        print("=" * 72)
        print("              RV64 IN-ORDER CORE: EXECUTION REPORT (PYNQ-Z2)")
        print("=" * 72)
        if not halted:
            print("  Status:               \033[31mTIMEOUT (core did not halt, still running)\033[0m")
        elif error:
            errpc = self.read64(REG_ERRPC_LO)
            inst  = self.ip.read((errpc & ~0x3) % MEM_BYTES)   # DMEM copy of the image
            print("  Status:               \033[31mHALTED ON ILLEGAL / UNSUPPORTED INSTRUCTION\033[0m")
            print(f"  Faulting PC:          0x{errpc:016X}")
            print(f"  Faulting instruction: 0x{inst:08X}  (note: DIV/REM are not supported)")
        else:
            print("  Status:               \033[32mHALTED ON WFI\033[0m")
        print(f"  Total Cycles:         {cycles}")
        print(f"  Retired Instructions: {retired}")
        if retired and cycles:
            print(f"  CPI:                  {cycles / retired:.3f}")
            print(f"  IPC:                  {retired / cycles:.3f}")
        print("=" * 72)

    def print_registers(self):
        print("  Architectural Registers (x0 - x31):")
        for i in range(0, 32, 2):
            cells = []
            for r in (i, i + 1):
                v = self.read64(REG_XREG + 8 * r)
                cells.append(f"x{r:<2} ({ABI_NAMES[r]:>4}): 0x{v:016X}")
            print("   " + "    ".join(cells))
        print("=" * 72)

    def print_memory(self, start=0x1000, count=10, all_nonzero=False):
        if all_nonzero:
            print("  Memory: all non-zero doublewords (hex : decimal)")
            addrs = [a for a in range(0, MEM_BYTES, 8) if self.read_dword(a) != 0]
        else:
            start &= ~0x7
            print(f"  Memory from 0x{start:04X} ({count} doublewords, hex : decimal)")
            addrs = [start + 8 * i for i in range(count)]
        print("-" * 72)
        for a in addrs:
            v = self.read_dword(a)
            print(f"   mem[0x{a:04X}] = 0x{v:016X} : {v}")
        print("=" * 72)


def main():
    ap = argparse.ArgumentParser(description="Run a program on the RV64 in-order core (PYNQ-Z2).")
    ap.add_argument("program", nargs="?", default="program.bin", help=".bin or .mem program image")
    ap.add_argument("--bit", default="rv64_core.bit", help="bitstream (.hwh with same basename alongside)")
    ap.add_argument("--clock", type=float, default=None, help="override FCLK0 in MHz (default: block design value)")
    ap.add_argument("--timeout", type=float, default=5.0, help="seconds to wait for halt")
    ap.add_argument("--mem-start", type=lambda x: int(x, 0), default=0x1000, help="memory dump start address")
    ap.add_argument("--mem-count", type=int, default=10, help="number of doublewords to dump")
    ap.add_argument("--mem-all", action="store_true", help="dump all non-zero doublewords instead")
    args = ap.parse_args()

    if not os.path.exists(args.program):
        sys.exit(f"Program '{args.program}' not found.")

    core = RV64InOrderFPGA(args.bit, args.clock)
    core.load_program(args.program)
    halted, error = core.run(args.timeout)
    core.print_stats(halted, error)
    core.print_registers()
    core.print_memory(args.mem_start, args.mem_count, args.mem_all)
    sys.exit(0 if (halted and not error) else 1)


if __name__ == "__main__":
    main()
