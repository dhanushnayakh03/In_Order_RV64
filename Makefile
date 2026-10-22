# ============================================================================
# Makefile for 5-Stage In-Order RV64 Core
# Simulator: Icarus Verilog (iverilog / vvp)
# Toolchain: riscv64-unknown-elf-gcc
# ============================================================================

# Toolchain definitions
CC      = riscv64-unknown-elf-gcc
OBJCOPY = riscv64-unknown-elf-objcopy
OBJDUMP = riscv64-unknown-elf-objdump
PYTHON  = python3

# Directories
SRC_DIR  = src
ASM_DIR  = test_assembly
C_DIR    = test_cprog
PROG_DIR = ../test_progs

# Compilation flags
CFLAGS   = -march=rv64i -mabi=lp64 -nostdlib -nostartfiles -T linker.ld
CFLAGS_C = -march=rv64i -mabi=lp64 -nostdlib -nostartfiles -O2 -T linker.ld
VFLAGS   = -g2001 -I$(SRC_DIR)

# Verilog source files
SRCS    = $(SRC_DIR)/rv64_defs.v \
          $(SRC_DIR)/regfile.v \
          $(SRC_DIR)/alu.v \
          $(SRC_DIR)/branch_cond.v \
          $(SRC_DIR)/forwarding_unit.v \
          $(SRC_DIR)/hazard_detection.v \
          $(SRC_DIR)/if_stage.v \
          $(SRC_DIR)/id_stage.v \
          $(SRC_DIR)/ex_stage.v \
          $(SRC_DIR)/mem_stage.v \
          $(SRC_DIR)/wb_stage.v \
          $(SRC_DIR)/pipeline_registers.v \
          $(SRC_DIR)/core_top.v \
          $(SRC_DIR)/memory.v \
          tb_core.v

VVP_OUT = tb_core.vvp

# Resolve assembly source file: checks current directory first, then test_assembly/
SOURCE ?= test_evens_64.s
ASM_FILE = $(if $(wildcard $(SOURCE)),$(SOURCE),$(if $(wildcard $(ASM_DIR)/$(SOURCE)),$(ASM_DIR)/$(SOURCE),$(error Error: Assembly file '$(SOURCE)' not found in '.' or '$(ASM_DIR)')))

# Resolve C source file: checks current directory, test_cprog/, or ../test_progs/
C_FILE = $(if $(wildcard $(SOURCE)),$(SOURCE),\
         $(if $(wildcard $(C_DIR)/$(SOURCE)),$(C_DIR)/$(SOURCE),\
         $(if $(wildcard $(PROG_DIR)/$(SOURCE)),$(PROG_DIR)/$(SOURCE),\
         $(error Error: C file '$(SOURCE)' not found in '.', '$(C_DIR)', or '$(PROG_DIR)'))))

.PHONY: all sim run program program_c run_c clean help

# Default: compile Verilog and run built-in self-checking test
all: run

# Compile Verilog testbench
sim: $(VVP_OUT)

$(VVP_OUT): $(SRCS)
	iverilog $(VFLAGS) -o $(VVP_OUT) $(SRCS)

# Run built-in self-checking test suite
run: $(VVP_OUT)
	vvp $(VVP_OUT)

# Assemble and run ANY assembly program from test_assembly/ or custom path
# Usage: make program SOURCE=test_evens_64.s
program: $(VVP_OUT)
	@echo "============================================================"
	@echo "Assembling: $(ASM_FILE)"
	@echo "============================================================"
	$(CC) $(CFLAGS) $(ASM_FILE) -o program.elf
	$(OBJDUMP) -d program.elf > program.dump
	$(OBJCOPY) -O binary program.elf program.bin
	$(PYTHON) make_hex.py program.bin program.mem
	@echo "============================================================"
	@echo "Running Simulation on In-Order RV64 Core..."
	@echo "============================================================"
	vvp $(VVP_OUT) +MEM=program.mem

# Compile C program to program.mem
# Usage: make program_c SOURCE=example.c
#    or: make program_c SOURCE=omegalul.c
program_c:
	@echo "============================================================"
	@echo "Compiling C Program: $(C_FILE)"
	@echo "============================================================"
	$(CC) $(CFLAGS_C) crt64.s $(C_FILE) -lgcc -o program.elf
	$(OBJDUMP) -d program.elf > program.dump
	$(OBJCOPY) -O binary program.elf program.bin
	$(PYTHON) make_hex.py program.bin program.mem
	@echo "============================================================"
	@echo "Generated program.mem successfully from $(C_FILE)!"
	@echo "============================================================"

# Compile C program and run simulation
# Usage: make run_c SOURCE=example.c
run_c: $(VVP_OUT) program_c
	@echo "============================================================"
	@echo "Running Simulation on In-Order RV64 Core..."
	@echo "============================================================"
	vvp $(VVP_OUT) +MEM=program.mem

clean:
	rm -f $(VVP_OUT) *.elf *.bin *.dump *.mem *.vcd

help:
	@echo "Available commands:"
	@echo "  make                       - Compile and run built-in testbench suite"
	@echo "  make program SOURCE=file.s - Assemble, convert, and simulate .s file"
	@echo "                               (e.g., make program SOURCE=test_evens_64.s)"
	@echo "  make program_c SOURCE=file.c - Compile C file and generate program.mem"
	@echo "                               (e.g., make program_c SOURCE=omegalul.c)"
	@echo "  make run_c SOURCE=file.c   - Compile C file to program.mem and simulate"
	@echo "  make clean                 - Clean generated simulation and binary files"
