// ============================================================================
// File: wb_stage.v
// Description: Writeback (WB) stage multiplexer
// Standard Verilog-2001
// ============================================================================

`include "rv64_defs.v"

module wb_stage (
    input  wire [`XLEN-1:0] alu_result,
    input  wire [`XLEN-1:0] load_data,
    input  wire [`XLEN-1:0] pc_plus_4,
    input  wire [1:0]       wb_sel,
    output reg  [`XLEN-1:0] wb_data
);

    always @(*) begin
        case (wb_sel)
            `WB_SEL_ALU: wb_data = alu_result;
            `WB_SEL_MEM: wb_data = load_data;
            `WB_SEL_PC4: wb_data = pc_plus_4;
            default:     wb_data = alu_result;
        endcase
    end

endmodule
