// ============================================================================
// tb_multiplier.v - waveform testbench for the 4-cycle multiplier in ex_stage.v
//   The testbench plays the role of the pipeline around EX:
//     - ID/EX : operands are held while mult_busy = 1 (stall), and the next
//               instruction is presented after the edge where mult_busy = 0
//     - EX/MEM1: exmem1_result captures alu_result on every edge where
//               mult_busy = 0 (exactly like ex_mem1_reg)
//   Op 10 takes operand A from the forwarding path (EX/MEM1 source); the
//   forwarded value is valid only in the op's first cycle and then changes to
//   a garbage value, as it does in the real pipeline during the stall.
//   VCD: tb/waves/tb_multiplier.vcd
// ============================================================================
`timescale 1ns/1ps
`include "rv64_defs.v"

module tb_multiplier;

    reg clk = 0;
    always #5 clk = ~clk;                       // rising edges at 5, 15, 25, ... ns
    reg rst = 1;

    localparam NOPS = 11;

    reg  [3:0]  idx = 0;                         // current instruction in EX
    reg  [2:0]  cyc_in_op = 0;                   // cycles this instruction has spent in EX

    // ---- instruction table
    reg [8*6-1:0] t_name [0:NOPS-1];
    reg [4:0]     t_ctrl [0:NOPS-1];
    reg [63:0]    t_a    [0:NOPS-1];
    reg [63:0]    t_b    [0:NOPS-1];
    reg [63:0]    t_exp  [0:NOPS-1];
    reg           t_fwd  [0:NOPS-1];

    initial begin
        t_name[0]  = "mul";    t_ctrl[0]  = `ALU_MUL;    t_a[0]  = 64'd7;                  t_b[0]  = 64'd6;                  t_exp[0]  = 64'h000000000000002A;
        t_name[1]  = "mul";    t_ctrl[1]  = `ALU_MUL;    t_a[1]  = -64'sd1;                t_b[1]  = -64'sd1;                t_exp[1]  = 64'h0000000000000001;
        t_name[2]  = "mulh";   t_ctrl[2]  = `ALU_MULH;   t_a[2]  = -64'sd1;                t_b[2]  = -64'sd1;                t_exp[2]  = 64'h0000000000000000;
        t_name[3]  = "mulhu";  t_ctrl[3]  = `ALU_MULHU;  t_a[3]  = -64'sd1;                t_b[3]  = -64'sd1;                t_exp[3]  = 64'hFFFFFFFFFFFFFFFE;
        t_name[4]  = "mulhsu"; t_ctrl[4]  = `ALU_MULHSU; t_a[4]  = -64'sd1;                t_b[4]  = -64'sd1;                t_exp[4]  = 64'hFFFFFFFFFFFFFFFF;
        t_name[5]  = "mulh";   t_ctrl[5]  = `ALU_MULH;   t_a[5]  = 64'h8000000000000000;   t_b[5]  = 64'h8000000000000000;   t_exp[5]  = 64'h4000000000000000;
        t_name[6]  = "mulh";   t_ctrl[6]  = `ALU_MULH;   t_a[6]  = 64'h8000000000000000;   t_b[6]  = -64'sd1;                t_exp[6]  = 64'h0000000000000000;
        t_name[7]  = "mulw";   t_ctrl[7]  = `ALU_MULW;   t_a[7]  = 64'h000000007FFFFFFF;   t_b[7]  = 64'd2;                  t_exp[7]  = 64'hFFFFFFFFFFFFFFFE;
        t_name[8]  = "mulw";   t_ctrl[8]  = `ALU_MULW;   t_a[8]  = 64'hDEADBEEF00000003;   t_b[8]  = 64'h1234567800000005;   t_exp[8]  = 64'h000000000000000F;
        t_name[9]  = "mulfwd"; t_ctrl[9]  = `ALU_MUL;    t_a[9]  = 64'h0000000000001234;   t_b[9]  = 64'h10;                 t_exp[9]  = 64'h0000000000012340;
        t_name[10] = "add";    t_ctrl[10] = `ALU_ADD;    t_a[10] = 64'd3;                  t_b[10] = 64'd4;                  t_exp[10] = 64'h0000000000000007;
        for (k = 0; k < NOPS; k = k + 1) t_fwd[k] = (k == 9);
    end
    integer k;

    // ---- ID/EX outputs feeding EX
    wire        valid    = !rst && (idx < NOPS);
    wire [8*6-1:0] op_name = valid ? t_name[idx] : "-";
    wire [4:0]  alu_ctrl = valid ? t_ctrl[idx] : `ALU_ADD;
    wire        use_fwd  = valid && t_fwd[idx];
    wire [63:0] rdata1   = valid ? (use_fwd ? 64'hFFFF_FFFF_FFFF_FFFF : t_a[idx]) : 64'd0; // stale RF value if forwarded
    wire [63:0] rdata2   = valid ? t_b[idx] : 64'd0;
    wire [1:0]  forward_a = use_fwd ? `FWD_FROM_MEM1 : `FWD_NONE;
    // forwarded source: correct value only in the first cycle, then the producer moves on
    wire [63:0] fwd_data_mem1 = !use_fwd ? 64'd0 : (cyc_in_op == 0 ? t_a[idx] : 64'h0BAD_0BAD_0BAD_0BAD);
    wire [63:0] exp_result = valid ? t_exp[idx] : 64'd0;

    wire [63:0] alu_result;
    wire        mult_busy;

    ex_stage dut (
        .clk(clk), .rst(rst),
        .pc(64'd0), .rdata1(rdata1), .rdata2(rdata2), .imm(64'd0),
        .alu_ctrl(alu_ctrl), .alua_sel(`ALUA_SEL_RS1), .alub_sel(`ALUB_SEL_RS2),
        .branch(1'b0), .jal(1'b0), .jalr(1'b0), .funct3(3'd0),
        .forward_a(forward_a), .forward_b(`FWD_NONE),
        .fwd_data_mem1(fwd_data_mem1), .fwd_data_mem2(64'd0), .fwd_data_wb(64'd0),
        .alu_result(alu_result), .store_data(), .branch_taken(), .branch_target(),
        .mult_busy(mult_busy));

    // internal multiplier state
    wire [1:0]  mult_cnt  = dut.mult_cnt;
    wire [63:0] hold_opa  = dut.mult_opa;
    wire [63:0] hold_opb  = dut.mult_opb;
    wire [63:0] operand_a = dut.alu_opa;     // after forwarding mux
    wire [63:0] operand_b = dut.alu_opb;

    // ---- EX/MEM1 register (captures when EX is not stalled)
    reg [63:0]    exmem1_result = 0;
    reg [8*6-1:0] exmem1_op     = "-";
    reg [63:0]    exmem1_exp    = 0;
    reg           exmem1_valid  = 0;
    wire          ok = !exmem1_valid || (exmem1_result === exmem1_exp);

    always @(posedge clk) begin
        if (rst) begin
            exmem1_valid <= 0;
        end else if (!mult_busy) begin
            exmem1_result <= alu_result;
            exmem1_op     <= op_name;
            exmem1_exp    <= exp_result;
            exmem1_valid  <= valid;
            if (valid) begin
                idx       <= idx + 1;
                cyc_in_op <= 0;
            end
        end else begin
            cyc_in_op <= cyc_in_op + 1;
        end
    end

    initial begin
        $dumpfile("waves/tb_multiplier.vcd");
        $dumpvars(1, tb_multiplier);
        repeat (2) @(posedge clk);
        rst <= 0;                                 // released on the 15 ns edge: op 1 is in EX from 15 ns
        wait (idx == NOPS);
        repeat (3) @(posedge clk);
        $finish;
    end

endmodule
