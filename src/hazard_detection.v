// ============================================================================
// File: hazard_detection.v
// Description: Stall / flush control for the 7-stage in-order pipeline
//                IF1 | IF2 | ID | EX | MEM1 | MEM2 | WB
//   Priority: taken branch > multiplier busy > halt drain > load-use
// Standard Verilog-2001
// ============================================================================

`include "rv64_defs.v"

module hazard_detection (
    // Instruction in ID
    input  wire [4:0]  if_id_rs1,
    input  wire [4:0]  if_id_rs2,
    input  wire        if_id_uses_rs1,
    input  wire        if_id_uses_rs2,
    input  wire        if_id_is_store,

    // Loads in flight (data available only once the load reaches WB)
    input  wire [4:0]  id_ex_rd,
    input  wire        id_ex_mem_read,
    input  wire [4:0]  ex_mem1_rd,
    input  wire        ex_mem1_mem_read,

    // Taken branch / jump resolved in EX
    input  wire        branch_taken,

    // Multiplier busy (4-cycle multiply occupying EX)
    input  wire        mult_busy,

    // WFI / illegal instruction in ID or beyond (or core halted)
    input  wire        stop_fetch,

    output reg         stall_pc,
    output reg         stall_if2,     // IF1/IF2 register + IMEM enable
    output reg         stall_if_id,
    output reg         stall_id_ex,
    output reg         flush_if2,
    output reg         flush_if_id,
    output reg         flush_id_ex,
    output reg         flush_ex_mem   // EX/MEM1
);

    // Load-use: an ID instruction needing a load result must wait until the
    // load is in WB (2 bubbles behind a load in EX, 1 behind a load in MEM1).
    // Exception: store data (rs2 of a store) is forwarded late in MEM1.
    // (Plain expressions, not a function reading module signals: a function
    //  that reads non-argument signals is not re-evaluated on their change.)
    wire hz_ex   = id_ex_mem_read && (id_ex_rd != 5'd0) &&
                   ((if_id_uses_rs1 && (id_ex_rd == if_id_rs1)) ||
                    (if_id_uses_rs2 && (id_ex_rd == if_id_rs2) && !if_id_is_store));

    wire hz_mem1 = ex_mem1_mem_read && (ex_mem1_rd != 5'd0) &&
                   ((if_id_uses_rs1 && (ex_mem1_rd == if_id_rs1)) ||
                    (if_id_uses_rs2 && (ex_mem1_rd == if_id_rs2) && !if_id_is_store));

    wire load_use_hazard = hz_ex || hz_mem1;

    always @(*) begin
        stall_pc     = 1'b0;
        stall_if2    = 1'b0;
        stall_if_id  = 1'b0;
        stall_id_ex  = 1'b0;
        flush_if2    = 1'b0;
        flush_if_id  = 1'b0;
        flush_id_ex  = 1'b0;
        flush_ex_mem = 1'b0;

        if (branch_taken) begin
            // Squash the 3 younger instructions in IF2 (via IF1/IF2), ID, EX-entry
            flush_if2   = 1'b1;
            flush_if_id = 1'b1;
            flush_id_ex = 1'b1;
        end
        else if (mult_busy) begin
            // Freeze everything up to EX, bubble into MEM1
            stall_pc     = 1'b1;
            stall_if2    = 1'b1;
            stall_if_id  = 1'b1;
            stall_id_ex  = 1'b1;
            flush_ex_mem = 1'b1;
        end
        else if (stop_fetch) begin
            // Halt drain: freeze PC, discard younger fetched instructions
            stall_pc    = 1'b1;
            flush_if2   = 1'b1;
            flush_if_id = 1'b1;
        end
        else if (load_use_hazard) begin
            stall_pc    = 1'b1;
            stall_if2   = 1'b1;
            stall_if_id = 1'b1;
            flush_id_ex = 1'b1;
        end
    end

endmodule
