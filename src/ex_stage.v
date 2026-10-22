// ============================================================================
// File: ex_stage.v
// Description: Execution (EX) stage with forwarding muxes, ALU, and branch logic
// Standard Verilog-2001
// ============================================================================

`include "rv64_defs.v"

module ex_stage (
    // Inputs from ID/EX pipeline register
    input  wire [`XLEN-1:0]      pc,
    input  wire [`XLEN-1:0]      rdata1,
    input  wire [`XLEN-1:0]      rdata2,
    input  wire [`XLEN-1:0]      imm,
    input  wire [4:0]            alu_ctrl,
    input  wire                  alua_sel,
    input  wire                  alub_sel,
    input  wire                  branch,
    input  wire                  jal,
    input  wire                  jalr,
    input  wire [2:0]            funct3,

    // Forwarding inputs
    input  wire [1:0]            forward_a,
    input  wire [1:0]            forward_b,
    input  wire [`XLEN-1:0]      fwd_data_ex,  // From EX/MEM stage
    input  wire [`XLEN-1:0]      fwd_data_mem, // From MEM/WB stage

    // Execution outputs
    output wire [`XLEN-1:0]      alu_result,
    output wire [`XLEN-1:0]      store_data,
    output wire                  branch_taken,
    output reg  [`XLEN-1:0]      branch_target
);

    // Forwarding Muxes for source operands
    reg [`XLEN-1:0] op1_forwarded;
    reg [`XLEN-1:0] op2_forwarded;

    always @(*) begin
        case (forward_a)
            `FWD_FROM_EX:  op1_forwarded = fwd_data_ex;
            `FWD_FROM_MEM: op1_forwarded = fwd_data_mem;
            default:       op1_forwarded = rdata1;
        endcase
    end

    always @(*) begin
        case (forward_b)
            `FWD_FROM_EX:  op2_forwarded = fwd_data_ex;
            `FWD_FROM_MEM: op2_forwarded = fwd_data_mem;
            default:       op2_forwarded = rdata2;
        endcase
    end

    // ALU input selection
    wire [`XLEN-1:0] alu_opa = (alua_sel == `ALUA_SEL_PC) ? pc : op1_forwarded;
    wire [`XLEN-1:0] alu_opb = (alub_sel == `ALUB_SEL_IMM) ? imm : op2_forwarded;

    // Store data is the forwarded rs2 value
    assign store_data = op2_forwarded;

    // Instantiate 64-bit ALU
    wire alu_zero;
    alu alu_inst (
        .opa      (alu_opa),
        .opb      (alu_opb),
        .alu_ctrl (alu_ctrl),
        .result   (alu_result),
        .zero     (alu_zero)
    );

    // Branch condition comparator
    wire cond_taken;
    branch_cond br_cond_inst (
        .rdata1 (op1_forwarded),
        .rdata2 (op2_forwarded),
        .funct3 (funct3),
        .taken  (cond_taken)
    );

    // Control hazard decision (branch taken or jump)
    assign branch_taken = (branch && cond_taken) || jal || jalr;

    // Target PC calculation
    always @(*) begin
        if (jalr) begin
            // JALR target is (rs1 + imm) with least-significant bit cleared
            branch_target = (op1_forwarded + imm) & ~64'd1;
        end else begin
            // Branch and JAL target is PC + imm
            branch_target = pc + imm;
        end
    end

endmodule
