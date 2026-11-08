// ============================================================================
// File: ex_stage.v
// Description: Execution (EX) stage with forwarding muxes, ALU, and branch logic
// Standard Verilog-2001
// ============================================================================

`include "rv64_defs.v"

module ex_stage (
    input  wire                  clk,
    input  wire                  rst,

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
    input  wire [`XLEN-1:0]      fwd_data_mem1, // From EX/MEM1 register
    input  wire [`XLEN-1:0]      fwd_data_mem2, // From MEM1/MEM2 register
    input  wire [`XLEN-1:0]      fwd_data_wb,   // From MEM2/WB register

    // Execution outputs
    output wire [`XLEN-1:0]      alu_result,
    output wire [`XLEN-1:0]      store_data,
    output wire                  branch_taken,
    output reg  [`XLEN-1:0]      branch_target,
    output wire                  mult_busy
);

    // Forwarding Muxes for source operands
    reg [`XLEN-1:0] op1_forwarded;
    reg [`XLEN-1:0] op2_forwarded;

    always @(*) begin
        case (forward_a)
            `FWD_FROM_MEM1: op1_forwarded = fwd_data_mem1;
            `FWD_FROM_MEM2: op1_forwarded = fwd_data_mem2;
            `FWD_FROM_WB:   op1_forwarded = fwd_data_wb;
            default:        op1_forwarded = rdata1;
        endcase
    end

    always @(*) begin
        case (forward_b)
            `FWD_FROM_MEM1: op2_forwarded = fwd_data_mem1;
            `FWD_FROM_MEM2: op2_forwarded = fwd_data_mem2;
            `FWD_FROM_WB:   op2_forwarded = fwd_data_wb;
            default:        op2_forwarded = rdata2;
        endcase
    end

    // ALU input selection
    wire [`XLEN-1:0] alu_opa = (alua_sel == `ALUA_SEL_PC) ? pc : op1_forwarded;
    wire [`XLEN-1:0] alu_opb = (alub_sel == `ALUB_SEL_IMM) ? imm : op2_forwarded;

    // Store data is the forwarded rs2 value
    assign store_data = op2_forwarded;

    // ------------------------------------------------------------------------
    // 4-Cycle Multiplier Unit (RV64M)
    // ------------------------------------------------------------------------
    wire is_mult = (alu_ctrl >= `ALU_MUL) && (alu_ctrl <= `ALU_MULW);
    reg [1:0] mult_cnt;
    reg [`XLEN-1:0] mult_opa;
    reg [`XLEN-1:0] mult_opb;
    assign mult_busy = is_mult && (mult_cnt != 2'd3);

    always @(posedge clk) begin
        if (rst) begin
            mult_cnt <= 2'd0;
            mult_opa <= 64'd0;
            mult_opb <= 64'd0;
        end else if (is_mult) begin
            if (mult_cnt == 2'd0) begin
                mult_opa <= alu_opa;
                mult_opb <= alu_opb;
            end
            if (mult_cnt == 2'd3)
                mult_cnt <= 2'd0;
            else
                mult_cnt <= mult_cnt + 2'd1;
        end else begin
            mult_cnt <= 2'd0;
        end
    end

    wire [`XLEN-1:0] in_a = (mult_cnt == 2'd0) ? alu_opa : mult_opa;
    wire [`XLEN-1:0] in_b = (mult_cnt == 2'd0) ? alu_opb : mult_opb;

    wire signed [63:0] s_a = in_a;
    wire signed [63:0] s_b = in_b;
    wire        [63:0] u_a = in_a;
    wire        [63:0] u_b = in_b;

    wire signed [127:0] prod_ss = s_a * s_b;
    wire signed [127:0] prod_su = s_a * $signed({1'b0, u_b});
    wire        [127:0] prod_uu = u_a * u_b;

    wire signed [31:0] s_a_w = in_a[31:0];
    wire signed [31:0] s_b_w = in_b[31:0];
    wire signed [63:0] prod_w = s_a_w * s_b_w;

    reg [`XLEN-1:0] mult_result;
    always @(*) begin
        case (alu_ctrl)
            `ALU_MUL:    mult_result = prod_ss[63:0];
            `ALU_MULH:   mult_result = prod_ss[127:64];
            `ALU_MULHSU: mult_result = prod_su[127:64];
            `ALU_MULHU:  mult_result = prod_uu[127:64];
            `ALU_MULW:   mult_result = {{32{prod_w[31]}}, prod_w[31:0]};
            default:      mult_result = prod_ss[63:0];
        endcase
    end

    // Instantiate 64-bit ALU for non-multiply operations
    wire alu_zero;
    wire [`XLEN-1:0] alu_raw_result;
    alu alu_inst (
        .opa      (alu_opa),
        .opb      (alu_opb),
        .alu_ctrl (alu_ctrl),
        .result   (alu_raw_result),
        .zero     (alu_zero)
    );

    // Mux final ALU result (Select Multiplier result when is_mult is active)
    assign alu_result = is_mult ? mult_result : alu_raw_result;


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
