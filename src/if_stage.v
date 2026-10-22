// ============================================================================
// File: if_stage.v
// Description: Instruction Fetch (IF) stage for RV64
// Standard Verilog-2001
// ============================================================================

`include "rv64_defs.v"

module if_stage (
    input  wire                  clk,
    input  wire                  rst,

    // Hazard / Control signals
    input  wire                  stall_pc,
    input  wire                  branch_taken,
    input  wire [`XLEN-1:0]      branch_target,

    // Instruction memory interface
    output wire [`XLEN-1:0]      imem_addr,
    
    // Outputs to IF/ID pipeline register
    output reg  [`XLEN-1:0]      pc,
    output wire [`XLEN-1:0]      pc_plus_4
);

    wire [`XLEN-1:0] next_pc;

    assign pc_plus_4 = pc + 64'd4;
    assign next_pc   = branch_taken ? branch_target : pc_plus_4;
    assign imem_addr = pc;

    always @(posedge clk) begin
        if (rst) begin
            pc <= {`XLEN{1'b0}};
        end else if (!stall_pc) begin
            pc <= next_pc;
        end
    end

endmodule
