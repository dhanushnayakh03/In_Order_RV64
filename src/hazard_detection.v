// ============================================================================
// File: hazard_detection.v
// Description: Hazard detection unit for Load-Use stalls and Control hazard flushes
// Standard Verilog-2001
// ============================================================================

`include "rv64_defs.v"

module hazard_detection (
    // Instruction currently in ID stage
    input  wire [4:0]  if_id_rs1,
    input  wire [4:0]  if_id_rs2,
    input  wire        if_id_uses_rs1,
    input  wire        if_id_uses_rs2,

    // Instruction currently in EX stage
    input  wire [4:0]  id_ex_rd,
    input  wire        id_ex_mem_read, // 1 if instruction in EX is a LOAD

    // Control hazard signal from EX stage (branch taken or jump)
    input  wire        branch_taken,

    // Stall and flush control outputs
    output reg         stall_pc,
    output reg         stall_if_id,
    output reg         flush_if_id,
    output reg         flush_id_ex
);

    wire load_use_hazard;

    // Load-use hazard detection:
    // If instruction in EX is a LOAD, and instruction in ID reads that destination register
    assign load_use_hazard = id_ex_mem_read && (id_ex_rd != 5'd0) &&
                            ((if_id_uses_rs1 && (id_ex_rd == if_id_rs1)) ||
                             (if_id_uses_rs2 && (id_ex_rd == if_id_rs2)));

    always @(*) begin
        // Default: no stalls, no flushes
        stall_pc    = 1'b0;
        stall_if_id = 1'b0;
        flush_if_id = 1'b0;
        flush_id_ex = 1'b0;

        // Control hazard (Branch taken / Jump in EX stage) has highest priority:
        // Crushes the 2 speculative instructions in IF/ID and ID/EX!
        if (branch_taken) begin
            flush_if_id = 1'b1;
            flush_id_ex = 1'b1;
        end
        // Data hazard: Load-use stall (1 cycle bubble)
        else if (load_use_hazard) begin
            stall_pc    = 1'b1; // Freeze PC
            stall_if_id = 1'b1; // Freeze IF/ID
            flush_id_ex = 1'b1; // Insert NOP bubble into ID/EX
        end
    end

endmodule
