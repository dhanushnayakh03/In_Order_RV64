// ============================================================================
// tb_forwarding.v - waveform testbench for forwarding_unit.v
//   One test case every 10 ns (case_id = 1, 2, ...).
//   Encoding of forward_a / forward_b:
//     00 = NONE (register file)   10 = EX/MEM1
//     11 = MEM1/MEM2              01 = MEM2/WB
//   fwd_a_src / fwd_b_src show the same as ASCII; exp_a / exp_b are the
//   expected codes; ok = 1 when both outputs match.
//   VCD: tb/waves/tb_forwarding.vcd
// ============================================================================
`timescale 1ns/1ps
`include "rv64_defs.v"

module tb_forwarding;

    reg  [7:0] case_id = 0;
    reg  [4:0] rs1 = 0, rs2 = 0;
    reg  [4:0] exmem1_rd = 0, mem1mem2_rd = 0, mem2wb_rd = 0;
    reg        exmem1_we = 0, mem1mem2_we = 0, mem2wb_we = 0;
    wire [1:0] forward_a, forward_b;
    reg  [1:0] exp_a = 0, exp_b = 0;

    forwarding_unit dut (
        .id_ex_rs1(rs1), .id_ex_rs2(rs2),
        .ex_mem1_rd(exmem1_rd),     .ex_mem1_reg_write(exmem1_we),
        .mem1_mem2_rd(mem1mem2_rd), .mem1_mem2_reg_write(mem1mem2_we),
        .mem_wb_rd(mem2wb_rd),      .mem_wb_reg_write(mem2wb_we),
        .forward_a(forward_a), .forward_b(forward_b));

    function [8*4-1:0] name(input [1:0] f);
        case (f)
            `FWD_FROM_MEM1: name = "MEM1";
            `FWD_FROM_MEM2: name = "MEM2";
            `FWD_FROM_WB:   name = "WB";
            default:        name = "NONE";
        endcase
    endfunction

    wire [8*4-1:0] fwd_a_src = name(forward_a);
    wire [8*4-1:0] fwd_b_src = name(forward_b);
    wire           ok = (forward_a === exp_a) && (forward_b === exp_b);

    localparam N = 2'b00, M1 = 2'b10, M2 = 2'b11, WB = 2'b01;

    task t(input [7:0] id,
           input [4:0] a, input [4:0] b,
           input [4:0] d1, input w1, input [4:0] d2, input w2, input [4:0] d3, input w3,
           input [1:0] ea, input [1:0] eb);
        begin
            case_id = id; rs1 = a; rs2 = b;
            exmem1_rd = d1; exmem1_we = w1;
            mem1mem2_rd = d2; mem1mem2_we = w2;
            mem2wb_rd = d3; mem2wb_we = w3;
            exp_a = ea; exp_b = eb;
            #10;
        end
    endtask

    initial begin
        $dumpfile("waves/tb_forwarding.vcd");
        $dumpvars(1, tb_forwarding);
        #10;
        //   id  rs1 rs2   EX/MEM1   MEM1/MEM2  MEM2/WB    exp_a exp_b
        t(1,   5,  6,    7, 1,     8, 1,      9, 1,      N,  N);   // no match
        t(2,   5,  6,    5, 1,     8, 1,      9, 1,      M1, N);   // rs1 <- EX/MEM1 (distance 1)
        t(3,   5,  6,    7, 1,     5, 1,      9, 1,      M2, N);   // rs1 <- MEM1/MEM2 (distance 2)
        t(4,   5,  6,    7, 1,     8, 1,      5, 1,      WB, N);   // rs1 <- MEM2/WB (distance 3)
        t(5,   5,  6,    7, 1,     8, 1,      6, 1,      N,  WB);  // rs2 <- MEM2/WB
        t(6,   5,  6,    5, 1,     8, 1,      6, 1,      M1, WB);  // rs1 and rs2 from different stages
        t(7,   5,  6,    5, 1,     5, 1,      5, 1,      M1, N);   // all three write x5: youngest wins
        t(8,   5,  6,    7, 1,     5, 1,      5, 1,      M2, N);   // MEM1/MEM2 younger than WB
        t(9,   5,  6,    5, 0,     8, 1,      5, 1,      WB, N);   // EX/MEM1 matches but no RegWrite
        t(10,  0,  0,    0, 1,     0, 1,      0, 1,      N,  N);   // x0 is never forwarded
        t(11,  5,  5,    5, 1,     8, 1,      9, 1,      M1, M1);  // rs1 = rs2 = x5
        t(12, 31, 31,    7, 1,    31, 1,      9, 1,      M2, M2);  // x31, both operands
        #10;
        $finish;
    end

endmodule
