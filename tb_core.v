// ============================================================================
// File: tb_core.v
// Description: Verification testbench for the 7-stage in-order RV64 core with
//              synchronous (BRAM-style) instruction and data memories.
//   make run                         built-in self-checking program
//   make program SOURCE=file.s       assemble + run (vvp tb_core.vvp +MEM=program.mem)
// The program image is loaded into both IMEM and DMEM, as the FPGA host does.
// Standard Verilog-2001
// ============================================================================

`timescale 1ns/100ps
`include "rv64_defs.v"

module tb_core;

    localparam MEM_BYTES = 65536;          // must match imem/dmem / FPGA wrapper
    localparam MEM_DEPTH = MEM_BYTES / 8;

    reg clk;
    reg rst;

    // Memory interconnect
    wire [`XLEN-1:0] imem_addr;
    wire             imem_en;
    wire [`ILEN-1:0] imem_rdata;

    wire [`XLEN-1:0] dmem_addr;
    wire [`XLEN-1:0] dmem_wdata;
    wire [7:0]       dmem_we;
    wire             dmem_en;
    wire [`XLEN-1:0] dmem_rdata;

    wire             halted;
    wire             error;
    wire [`XLEN-1:0] error_pc;
    wire [31:0]      cycle_count;
    wire [31:0]      retired_inst_count;

    core_top dut (
        .clk                (clk),
        .rst                (rst),
        .imem_addr          (imem_addr),
        .imem_en            (imem_en),
        .imem_rdata         (imem_rdata),
        .dmem_addr          (dmem_addr),
        .dmem_wdata         (dmem_wdata),
        .dmem_we            (dmem_we),
        .dmem_en            (dmem_en),
        .dmem_rdata         (dmem_rdata),
        .halted             (halted),
        .error              (error),
        .error_pc           (error_pc),
        .cycle_count        (cycle_count),
        .retired_inst_count (retired_inst_count),
        .dbg_reg_addr       (5'd0),
        .dbg_reg_data       ()
    );

    // Host ports unused in simulation (memories preloaded below)
    imem #(.MEM_SIZE_BYTES(MEM_BYTES)) imem_inst (
        .clk        (clk),
        .en         (imem_en),
        .addr       (imem_addr),
        .rdata      (imem_rdata),
        .host_we    (1'b0),
        .host_addr  (32'd0),
        .host_wstrb (4'd0),
        .host_wdata (32'd0)
    );

    dmem #(.MEM_SIZE_BYTES(MEM_BYTES)) dmem_inst (
        .clk        (clk),
        .en         (dmem_en),
        .we         (dmem_we),
        .addr       (dmem_addr),
        .wdata      (dmem_wdata),
        .rdata      (dmem_rdata),
        .host_en    (1'b0),
        .host_wstrb (4'd0),
        .host_addr  (32'd0),
        .host_wdata (32'd0),
        .host_rdata ()
    );

    // Clock generation: 10 ns period
    always begin
        #5 clk = ~clk;
    end

    integer k;
    reg [8*256-1:0] mem_file;   // up to 256-char +MEM= path
    reg mem_file_loaded;

    initial begin
        clk = 0;
        rst = 1;
        mem_file_loaded = 0;

        for (k = 0; k < MEM_DEPTH; k = k + 1) begin
            imem_inst.mem_array[k] = 64'd0;
            dmem_inst.mem_array[k] = 64'd0;
        end

        if ($value$plusargs("MEM=%s", mem_file)) begin
            mem_file_loaded = 1;
            $display("Loading memory from file: %0s", mem_file);
            $readmemh(mem_file, imem_inst.mem_array);
            $readmemh(mem_file, dmem_inst.mem_array);
        end else begin
            $display("Loading built-in self-checking verification program...");
            // 0x00: ADDI x1, x0, 10      x1 = 10
            // 0x04: ADDI x2, x0, 20      x2 = 20
            // 0x08: ADD  x3, x1, x2      RAW forwarding: x3 = 30
            // 0x0C: SUB  x4, x3, x1      RAW forwarding: x4 = 20
            // 0x10: SD   x3, 0x100(x0)   mem[0x100] = 30
            // 0x14: LD   x5, 0x100(x0)   store -> load same address
            // 0x18: ADDI x6, x5, 5       load-use: x6 = 35
            // 0x1C: BEQ  x4, x2, 8       taken -> 0x24
            // 0x20: ADDI x7, x0, 99      squashed
            // 0x24: ADDI x8, x0, 42      x8 = 42
            // 0x28: SD   x8, 0x108(x0)   mem[0x108] = 42
            // 0x2C: WFI
            imem_inst.mem_array[0] = {32'h01400113, 32'h00a00093};
            imem_inst.mem_array[1] = {32'h40118233, 32'h002081b3};
            imem_inst.mem_array[2] = {32'h10003283, 32'h10303023};
            imem_inst.mem_array[3] = {32'h00220463, 32'h00528313};
            imem_inst.mem_array[4] = {32'h02a00413, 32'h06300393};
            imem_inst.mem_array[5] = {32'h10500073, 32'h10803423};
            for (k = 0; k < 6; k = k + 1)
                dmem_inst.mem_array[k] = imem_inst.mem_array[k];
        end

        #20;
        rst = 0;
        $display("[%0t ns] Reset deasserted. Processor running...", $time);

        #2000000;
        $display("ERROR: Simulation timeout reached without WFI halt!");
        $finish;
    end

    // Halt monitor
    always @(posedge clk) begin
        if (!rst && halted) begin
            $display("------------------------------------------------------------");
            if (error) begin
                $display("\033[31m>>> SYSTEM HALTED ON ILLEGAL / UNSUPPORTED INSTRUCTION <<<\033[0m");
                $display("  Faulting PC:              0x%016x", error_pc);
                $display("  Faulting instruction:     0x%08x (note: DIV/REM are not supported)",
                         error_pc[2] ? imem_inst.mem_array[(error_pc >> 3) % MEM_DEPTH][63:32]
                                     : imem_inst.mem_array[(error_pc >> 3) % MEM_DEPTH][31:0]);
            end else begin
                $display(">>> SYSTEM HALTED ON WFI INSTRUCTION <<<");
            end
            $display("Execution Statistics:");
            $display("  Total Clock Cycles:       %0d", cycle_count);
            $display("  Retired Instructions:     %0d", retired_inst_count);
            $display("------------------------------------------------------------");

            $display("Architectural registers:");
            for (k = 0; k < 32; k = k + 1)
                $display("  x%0d = %016x", k, (k == 0) ? 64'd0 : dut.id_inst.rf.regs[k]);
            $display("------------------------------------------------------------");

            $display("@@@ Data Memory contents hex on left, decimal on right: ");
            $display("@@@");
            for (k = 0; k < MEM_DEPTH; k = k + 1) begin
                if (dmem_inst.mem_array[k] != 64'd0) begin
                    $display("@@@ mem[%5d] = %016x : %0d", k * 8, dmem_inst.mem_array[k], dmem_inst.mem_array[k]);
                end
            end
            $display("@@@");
            if (error)
                $display("@@@ System halted on illegal instruction at PC 0x%0x", error_pc);
            else
                $display("@@@ System halted on WFI instruction");
            $display("------------------------------------------------------------");

            if (error) begin
                $display("\033[31m>>> PROGRAM TERMINATED WITH ERROR <<<\033[0m");
            end else if (!mem_file_loaded) begin
                if (dut.id_inst.rf.regs[3] == 64'd30 &&
                    dut.id_inst.rf.regs[4] == 64'd20 &&
                    dut.id_inst.rf.regs[5] == 64'd30 &&
                    dut.id_inst.rf.regs[6] == 64'd35 &&
                    dut.id_inst.rf.regs[7] == 64'd0  &&
                    dut.id_inst.rf.regs[8] == 64'd42 &&
                    dmem_inst.mem_array[32'h108 >> 3] == 64'd42) begin
                    $display("\033[32m>>> ALL CHECKS PASSED SUCCESSFULLY! <<<\033[0m");
                    $display("1. RAW Data Forwarding:                  PASSED");
                    $display("2. Store -> Load same address:           PASSED");
                    $display("3. Load-Use Hazard Stall:                PASSED");
                    $display("4. Branch Taken & Squashing:             PASSED");
                    $display("5. 64-bit Memory Store (SD) & Load (LD): PASSED");
                end else begin
                    $display("\033[31m>>> VERIFICATION FAILED! <<<\033[0m");
                    $display("Register state: x3=%0d, x4=%0d, x5=%0d, x6=%0d, x7=%0d, x8=%0d",
                        dut.id_inst.rf.regs[3], dut.id_inst.rf.regs[4], dut.id_inst.rf.regs[5],
                        dut.id_inst.rf.regs[6], dut.id_inst.rf.regs[7], dut.id_inst.rf.regs[8]);
                end
            end else begin
                $display("\033[32m>>> PROGRAM EXECUTION COMPLETED SUCCESSFULLY! <<<\033[0m");
            end

            $finish;
        end
    end

endmodule
