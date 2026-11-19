#!/usr/bin/env python3
# ============================================================================
# File: test_rv64.py
# Description: Automated Python / Jupyter Verification Suite for RV64 on PYNQ-Z2
# Usage:
#   In Jupyter Notebook:
#     import test_rv64 as rv
#     t = rv.RV64Tester("rv64_core.bit")
#     t.run_program("program.bin")
#     t.print_memory(0x1000, count=10)
# ============================================================================

import time
import struct
from pynq import Overlay

class RV64Tester:
    def __init__(self, bitstream_path="rv64_core.bit"):
        """Initializes the PYNQ overlay and hooks the RV64 processor core."""
        print(f"[PYNQ] Loading bitstream: {bitstream_path} ...")
        self.ol = Overlay(bitstream_path)
        
        # Access the AXI4-Lite interface of rv64_pynq_top
        # In Vivado, this is typically named 'rv64_pynq_top_0'
        if hasattr(self.ol, "rv64_pynq_top_0"):
            self.core = self.ol.rv64_pynq_top_0
        else:
            # Fallback: grab the first IP block in the overlay
            ip_name = list(self.ol.ip_dict.keys())[0]
            self.core = getattr(self.ol, ip_name)
            
        print("[PYNQ] RV64 Core connected successfully.")

    def reset(self, state=True):
        """Asserts (True) or deasserts (False) CPU reset."""
        self.core.write(0x10000, 1 if state else 0)

    def is_halted(self):
        """Returns True if CPU reached WFI instruction."""
        return (self.core.read(0x10004) & 1) == 1

    def get_cycles(self):
        """Reads hardware cycle count."""
        return self.core.read(0x10008)

    def get_instructions(self):
        """Reads total retired instructions."""
        return self.core.read(0x1000C)

    def write_mem_word(self, byte_addr, val32):
        """Writes a 32-bit word into RV64 memory."""
        self.core.write(byte_addr & 0xFFFF, int(val32))

    def read_mem_word(self, byte_addr):
        """Reads a 32-bit word from RV64 memory."""
        return self.core.read(byte_addr & 0xFFFF)

    def read_mem_doubleword(self, byte_addr):
        """Reads a 64-bit doubleword from RV64 memory."""
        low  = self.core.read(byte_addr & 0xFFFF)
        high = self.core.read((byte_addr + 4) & 0xFFFF)
        return (high << 32) | low

    def load_binary(self, bin_path):
        """Loads a compiled .bin file into memory starting at 0x0000."""
        self.reset(True) # Hold in reset while writing memory
        with open(bin_path, "rb") as f:
            code = f.read()

        # Pad to multiple of 4 bytes
        while len(code) % 4 != 0:
            code += b'\x00'

        print(f"[PYNQ] Writing {len(code)} bytes into RV64 RAM starting at 0x0000 ...")
        for i in range(0, len(code), 4):
            word = struct.unpack("<I", code[i:i+4])[0]
            self.write_mem_word(i, word)

        print("[PYNQ] Memory load complete.")

    def run_program(self, bin_path, timeout_sec=2.0):
        """Loads binary, resets CPU, executes, and displays performance report."""
        self.load_binary(bin_path)

        print("[PYNQ] Releasing Reset -> Processor Running...")
        start_time = time.time()
        self.reset(False) # Release reset

        # Wait for halt
        while not self.is_halted():
            if time.time() - start_time > timeout_sec:
                print(f"\033[31m[ERROR] Execution timed out after {timeout_sec}s without WFI halt!\033[0m")
                return False

        cycles = self.get_cycles()
        insts  = self.get_instructions()
        cpi    = cycles / insts if insts > 0 else 0.0

        print("=" * 64)
        print("          RV64 EXECUTION REPORT (PYNQ-Z2)")
        print("=" * 64)
        print(f"  Status:               HALTED ON WFI")
        print(f"  Total Cycles:         {cycles}")
        print(f"  Retired Instructions: {insts}")
        print(f"  Measured CPI:         {cpi:.2f} cycles/instruction")
        print("=" * 64)
        return True

    def print_memory(self, start_addr=0x1000, count=10):
        """Prints formatted 64-bit memory contents (hex and decimal)."""
        print(f"\n>> Memory Contents starting at 0x{start_addr:X} (64-bit doublewords):")
        print("-" * 55)
        for i in range(count):
            addr = start_addr + (i * 8)
            val  = self.read_mem_doubleword(addr)
            print(f"  mem[0x{addr:04X}] = 0x{val:016X} : {val}")
        print("-" * 55)

if __name__ == "__main__":
    import sys
    bin_file = sys.argv[1] if len(sys.argv) > 1 else "program.bin"
    tester = RV64Tester()
    if tester.run_program(bin_file):
        tester.print_memory(0x1000, count=10)
