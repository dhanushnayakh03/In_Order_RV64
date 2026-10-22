// ============================================================================
// File: tb_core.v
// Description: Comprehensive Verification Testbench for 5-stage In-Order RV64 Core
// Tests RAW Forwarding, Load-Use Stall, Branch Squashing, and Memory Ops
// Standard Verilog-2001
// ============================================================================

`timescale 1ns/100ps
`include "rv64_defs.v"

module tb_core;

    reg clk;
    reg rst;

    // Memory Interconnects
    wire [`XLEN-1:0] imem_addr;
    wire [`ILEN-1:0] imem_rdata;

    wire [`XLEN-1:0] dmem_addr;
    wire [`XLEN-1:0] dmem_wdata;
    wire [7:0]       dmem_byte_en;
    wire             dmem_en;
    wire             dmem_wen;
    wire [`XLEN-1:0] dmem_rdata;

    wire             halted;
    wire [31:0]      cycle_count;
    wire [31:0]      retired_inst_count;

    // Instantiate RV64 Core Top
    core_top dut (
        .clk                (clk),
        .rst                (rst),
        .imem_addr          (imem_addr),
        .imem_rdata         (imem_rdata),
        .dmem_addr          (dmem_addr),
        .dmem_wdata         (dmem_wdata),
        .dmem_byte_en       (dmem_byte_en),
        .dmem_en            (dmem_en),
        .dmem_wen           (dmem_wen),
        .dmem_rdata         (dmem_rdata),
        .halted             (halted),
        .cycle_count        (cycle_count),
        .retired_inst_count (retired_inst_count)
    );

    // Instantiate Dual-Port Memory
    memory #(
        .MEM_SIZE_BYTES (65536)
    ) mem_inst (
        .clk          (clk),
        .rst          (rst),
        .imem_addr    (imem_addr),
        .imem_rdata   (imem_rdata),
        .dmem_addr    (dmem_addr),
        .dmem_wdata   (dmem_wdata),
        .dmem_byte_en (dmem_byte_en),
        .dmem_en      (dmem_en),
        .dmem_wen     (dmem_wen),
        .dmem_rdata   (dmem_rdata)
    );

    // Clock generation: 10 ns period (100 MHz)
    always begin
        #5 clk = ~clk;
    end

    integer k;
    reg [255:0] mem_file;
    reg mem_file_loaded;

    initial begin
        clk = 0;
        rst = 1;
        mem_file_loaded = 0;

        // Initialize memory with zeros
        for (k = 0; k < 8192; k = k + 1) begin
            mem_inst.mem_array[k] = 64'd0;
        end

        // Check if a +MEM=program.mem argument was provided, else use built-in test program
        if ($value$plusargs("MEM=%s", mem_file)) begin
            mem_file_loaded = 1;
            $display("Loading memory from file: %s", mem_file);
            $readmemh(mem_file, mem_inst.mem_array);
        end else begin
            $display("Loading built-in self-checking verification program...");
            // Built-in test program:
            // 0x00: ADDI x1, x0, 10           (x1 = 10)
            // 0x04: ADDI x2, x0, 20           (x2 = 20)
            // 0x08: ADD  x3, x1, x2           (RAW Forwarding test: x3 = 30)
            // 0x0C: SUB  x4, x3, x1           (RAW Forwarding test: x4 = 20)
            // 0x10: SD   x3, 0x100(x0)        (Store 30 to mem[0x100])
            // 0x14: LD   x5, 0x100(x0)        (Load from mem[0x100])
            // 0x18: ADDI x6, x5, 5            (Load-Use hazard: x6 = 35, must stall 1 cycle!)
            // 0x1C: BEQ  x4, x2, 8            (Branch test: 20 == 20 -> Taken! Jump to 0x24)
            // 0x20: ADDI x7, x0, 99           (Should be SQUASHED / killed!)
            // 0x24: ADDI x8, x0, 42           (x8 = 42)
            // 0x28: SD   x8, 0x108(x0)        (Store 42 to mem[0x108])
            // 0x2C: WFI                       (Halt)
            
            // Stored in 64-bit lines (2 instructions per line):
            // Line 0: {0x04, 0x00}
            mem_inst.mem_array[0] = {32'h01400113, 32'h00a00093}; // addi x2, x0, 20 | addi x1, x0, 10
            // Line 1: {0x0C, 0x08}
            mem_inst.mem_array[1] = {32'h40118233, 32'h002081b3}; // sub x4, x3, x1  | add x3, x1, x2
            // Line 2: {0x14, 0x10}
            mem_inst.mem_array[2] = {32'h10003283, 32'h10303023}; // ld x5, 0x100(x0) | sd x3, 0x100(x0)
            // Line 3: {0x1C, 0x18}
            mem_inst.mem_array[3] = {32'h00220463, 32'h00528313}; // beq x4, x2, 8   | addi x6, x5, 5
            // Line 4: {0x24, 0x20}
            mem_inst.mem_array[4] = {32'h02a00413, 32'h06300393}; // addi x8, x0, 42  | addi x7, x0, 99 (SQUASHED!)
            // Line 5: {0x2C, 0x28}
            mem_inst.mem_array[5] = {32'h10500073, 32'h10803423}; // wfi (halt)      | sd x8, 0x108(x0)
        end

        // Release reset after 20 ns
        #20;
        rst = 0;
        $display("[%0t ns] Reset deasserted. Processor running...", $time);

        // Simulation timeout watchdog (100,000 cycles)
        #1000000;
        $display("ERROR: Simulation timeout reached without WFI halt!");
        $finish;
    end

    // Monitor Halt condition
    always @(posedge clk) begin
        if (!rst && halted) begin
            $display("------------------------------------------------------------");
            $display(">>> SYSTEM HALTED ON WFI INSTRUCTION <<<");
            $display("Execution Statistics:");
            $display("  Total Clock Cycles:       %0d", cycle_count);
            $display("  Retired Instructions:     %0d", retired_inst_count);
            $display("------------------------------------------------------------");

            // Dump non-zero memory
            $display("@@@ Unified Memory contents hex on left, decimal on right: ");
            $display("@@@");
            for (k = 0; k < 8192; k = k + 1) begin
                if (mem_inst.mem_array[k] != 64'd0) begin
                    $display("@@@ mem[%5d] = %016x : %0d", k * 8, mem_inst.mem_array[k], mem_inst.mem_array[k]);
                end
            end
            $display("@@@");
            $display("@@@ System halted on WFI instruction");
            $display("------------------------------------------------------------");

            // Self-checking verification checks for built-in test
            if (!mem_file_loaded) begin
                if (dut.id_inst.rf.regs[3] == 64'd30 && // x3 = 30 (Forwarding passed)
                    dut.id_inst.rf.regs[4] == 64'd20 && // x4 = 20 (Forwarding passed)
                    dut.id_inst.rf.regs[6] == 64'd35 && // x6 = 35 (Load-use stall passed)
                    dut.id_inst.rf.regs[7] == 64'd0  && // x7 = 0  (Branch squashing passed, inst was killed!)
                    dut.id_inst.rf.regs[8] == 64'd42    // x8 = 42 (Branch target reached)
                ) begin
                    $display("\033[32m>>> ALL CHECKS PASSED SUCCESSFULLY! <<<\033[0m");
                    $display("1. RAW Data Forwarding (EX->EX, MEM->EX): PASSED");
                    $display("2. Load-Use Hazard Stall:                 PASSED");
                    $display("3. Branch Taken & 2-Inst Squashing:       PASSED");
                    $display("4. 64-bit Memory Store (SD) & Load (LD):  PASSED");
                end else begin
                    $display("\033[31m>>> VERIFICATION FAILED! <<<\033[0m");
                    $display("Register state: x3=%0d, x4=%0d, x6=%0d, x7=%0d, x8=%0d",
                        dut.id_inst.rf.regs[3], dut.id_inst.rf.regs[4],
                        dut.id_inst.rf.regs[6], dut.id_inst.rf.regs[7], dut.id_inst.rf.regs[8]);
                end
            end else begin
                $display("\033[32m>>> PROGRAM EXECUTION COMPLETED SUCCESSFULLY! <<<\033[0m");
            end

            $finish;
        end
    end

endmodule
