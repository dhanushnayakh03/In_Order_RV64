// ============================================================================
// File: forwarding_unit.v
// Description: EX-stage operand forwarding for the 7-stage pipeline.
//   Sources, youngest first: EX/MEM1, MEM1/MEM2, MEM2/WB (all registers).
//   A load still in MEM1/MEM2 only carries its address; a dependent ALU /
//   branch / address use is stalled by the hazard unit, and a dependent store
//   data use is re-forwarded in MEM1, so forwarding the address is harmless.
// Standard Verilog-2001
// ============================================================================

`include "rv64_defs.v"

module forwarding_unit (
    input  wire [4:0]  id_ex_rs1,
    input  wire [4:0]  id_ex_rs2,

    input  wire [4:0]  ex_mem1_rd,
    input  wire        ex_mem1_reg_write,
    input  wire [4:0]  mem1_mem2_rd,
    input  wire        mem1_mem2_reg_write,
    input  wire [4:0]  mem_wb_rd,
    input  wire        mem_wb_reg_write,

    output reg  [1:0]  forward_a,
    output reg  [1:0]  forward_b
);

    function [1:0] fwd_sel;
        input [4:0] rs;
        input [4:0] rd1; input we1;
        input [4:0] rd2; input we2;
        input [4:0] rd3; input we3;
        begin
            if      (we1 && (rd1 != 5'd0) && (rd1 == rs)) fwd_sel = `FWD_FROM_MEM1;
            else if (we2 && (rd2 != 5'd0) && (rd2 == rs)) fwd_sel = `FWD_FROM_MEM2;
            else if (we3 && (rd3 != 5'd0) && (rd3 == rs)) fwd_sel = `FWD_FROM_WB;
            else                                          fwd_sel = `FWD_NONE;
        end
    endfunction

    always @(*) begin
        forward_a = fwd_sel(id_ex_rs1, ex_mem1_rd, ex_mem1_reg_write,
                            mem1_mem2_rd, mem1_mem2_reg_write, mem_wb_rd, mem_wb_reg_write);
        forward_b = fwd_sel(id_ex_rs2, ex_mem1_rd, ex_mem1_reg_write,
                            mem1_mem2_rd, mem1_mem2_reg_write, mem_wb_rd, mem_wb_reg_write);
    end

endmodule
