// ============================================================================
// File: branch_cond.v
// Description: Branch condition comparator for RV64 conditional branches
// Standard Verilog-2001
// ============================================================================

`include "rv64_defs.v"

module branch_cond (
    input  wire [`XLEN-1:0]      rdata1,
    input  wire [`XLEN-1:0]      rdata2,
    input  wire [2:0]            funct3,
    output reg                   taken
);

    wire signed [`XLEN-1:0] signed_r1 = rdata1;
    wire signed [`XLEN-1:0] signed_r2 = rdata2;

    always @(*) begin
        case (funct3)
            `FUNCT3_BEQ:  taken = (rdata1 == rdata2);
            `FUNCT3_BNE:  taken = (rdata1 != rdata2);
            `FUNCT3_BLT:  taken = (signed_r1 < signed_r2);
            `FUNCT3_BGE:  taken = (signed_r1 >= signed_r2);
            `FUNCT3_BLTU: taken = (rdata1 < rdata2);
            `FUNCT3_BGEU: taken = (rdata1 >= rdata2);
            default:      taken = 1'b0;
        endcase
    end

endmodule
