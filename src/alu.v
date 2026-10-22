// ============================================================================
// File: alu.v
// Description: 64-bit RV64I Arithmetic Logic Unit (ALU)
// Supports full 64-bit operations and 32-bit W-instructions
// Standard Verilog-2001
// ============================================================================

`include "rv64_defs.v"

module alu (
    input  wire [`XLEN-1:0]      opa,
    input  wire [`XLEN-1:0]      opb,
    input  wire [4:0]            alu_ctrl,
    output reg  [`XLEN-1:0]      result,
    output wire                  zero
);

    wire signed [`XLEN-1:0] signed_opa = opa;
    wire signed [`XLEN-1:0] signed_opb = opb;

    // 32-bit slices for W-instructions
    wire [31:0] opa32 = opa[31:0];
    wire [31:0] opb32 = opb[31:0];
    wire signed [31:0] signed_opa32 = opa[31:0];

    reg [31:0] res32;

    always @(*) begin
        res32 = 32'd0;
        case (alu_ctrl)
            `ALU_ADD:    result = opa + opb;
            `ALU_SUB:    result = opa - opb;
            `ALU_SLL:    result = opa << opb[5:0];
            `ALU_SLT:    result = (signed_opa < signed_opb) ? 64'd1 : 64'd0;
            `ALU_SLTU:   result = (opa < opb) ? 64'd1 : 64'd0;
            `ALU_XOR:    result = opa ^ opb;
            `ALU_SRL:    result = opa >> opb[5:0];
            `ALU_SRA:    result = signed_opa >>> opb[5:0];
            `ALU_OR:     result = opa | opb;
            `ALU_AND:    result = opa & opb;

            // 32-bit W-instructions (truncated to 32 bits, then sign-extended to 64 bits)
            `ALU_ADDW: begin
                res32  = opa32 + opb32;
                result = {{32{res32[31]}}, res32};
            end
            `ALU_SUBW: begin
                res32  = opa32 - opb32;
                result = {{32{res32[31]}}, res32};
            end
            `ALU_SLLW: begin
                res32  = opa32 << opb32[4:0];
                result = {{32{res32[31]}}, res32};
            end
            `ALU_SRLW: begin
                res32  = opa32 >> opb32[4:0];
                result = {{32{res32[31]}}, res32};
            end
            `ALU_SRAW: begin
                res32  = signed_opa32 >>> opb32[4:0];
                result = {{32{res32[31]}}, res32};
            end

            `ALU_PASS_B: result = opb;

            default:     result = {`XLEN{1'b0}};
        endcase
    end

    assign zero = (result == {`XLEN{1'b0}});

endmodule
