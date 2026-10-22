// ============================================================================
// File: forwarding_unit.v
// Description: Data hazard forwarding unit (EX/MEM and MEM/WB forwarding to EX)
// Standard Verilog-2001
// ============================================================================

`include "rv64_defs.v"

module forwarding_unit (
    // Source registers from ID/EX stage
    input  wire [4:0]  id_ex_rs1,
    input  wire [4:0]  id_ex_rs2,

    // Destination register and write enable from EX/MEM stage
    input  wire [4:0]  ex_mem_rd,
    input  wire        ex_mem_reg_write,

    // Destination register and write enable from MEM/WB stage
    input  wire [4:0]  mem_wb_rd,
    input  wire        mem_wb_reg_write,

    // Forwarding select signals to EX stage
    output reg  [1:0]  forward_a,
    output reg  [1:0]  forward_b
);

    // Forwarding for Operand A (rs1)
    always @(*) begin
        // Priority 1: EX/MEM hazard (most recent instruction)
        if (ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs1)) begin
            forward_a = `FWD_FROM_EX; // 2'b10
        end
        // Priority 2: MEM/WB hazard (older instruction)
        else if (mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs1)) begin
            forward_a = `FWD_FROM_MEM; // 2'b01
        end
        // No hazard
        else begin
            forward_a = `FWD_NONE; // 2'b00
        end
    end

    // Forwarding for Operand B (rs2)
    always @(*) begin
        // Priority 1: EX/MEM hazard
        if (ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs2)) begin
            forward_b = `FWD_FROM_EX; // 2'b10
        end
        // Priority 2: MEM/WB hazard
        else if (mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs2)) begin
            forward_b = `FWD_FROM_MEM; // 2'b01
        end
        // No hazard
        else begin
            forward_b = `FWD_NONE; // 2'b00
        end
    end

endmodule
