// ============================================================================
// tb_hazard.v - waveform testbench for hazard_detection.v
//   One scenario every 10 ns (case_id = 1, 2, ...). `scenario` is an ASCII
//   label. All 8 outputs are also packed into `ctrl` (MSB first):
//     ctrl = {stall_pc, stall_if2, stall_if_id, stall_id_ex,
//             flush_if2, flush_if_id, flush_id_ex, flush_ex_mem}
//   exp_ctrl is the expected value; ok = 1 when they match.
//   Patterns:  load-use   = 1110_0010  (E2)
//              mult busy  = 1111_0001  (F1)
//              stop fetch = 1000_1100  (8C)
//              branch     = 0000_1110  (0E)
//              none       = 0000_0000  (00)
//   VCD: tb/waves/tb_hazard.vcd
// ============================================================================
`timescale 1ns/1ps

module tb_hazard;

    reg  [7:0]      case_id = 0;
    reg  [8*16-1:0] scenario = "RESET";

    reg  [4:0] id_rs1 = 0, id_rs2 = 0;
    reg        id_uses_rs1 = 0, id_uses_rs2 = 0, id_is_store = 0;
    reg  [4:0] idex_rd = 0;
    reg        idex_mem_read = 0;
    reg  [4:0] exmem1_rd = 0;
    reg        exmem1_mem_read = 0;
    reg        branch_taken = 0, mult_busy = 0, stop_fetch = 0;

    wire stall_pc, stall_if2, stall_if_id, stall_id_ex;
    wire flush_if2, flush_if_id, flush_id_ex, flush_ex_mem;

    hazard_detection dut (
        .if_id_rs1(id_rs1), .if_id_rs2(id_rs2),
        .if_id_uses_rs1(id_uses_rs1), .if_id_uses_rs2(id_uses_rs2), .if_id_is_store(id_is_store),
        .id_ex_rd(idex_rd), .id_ex_mem_read(idex_mem_read),
        .ex_mem1_rd(exmem1_rd), .ex_mem1_mem_read(exmem1_mem_read),
        .branch_taken(branch_taken), .mult_busy(mult_busy), .stop_fetch(stop_fetch),
        .stall_pc(stall_pc), .stall_if2(stall_if2), .stall_if_id(stall_if_id), .stall_id_ex(stall_id_ex),
        .flush_if2(flush_if2), .flush_if_id(flush_if_id), .flush_id_ex(flush_id_ex),
        .flush_ex_mem(flush_ex_mem));

    wire [7:0] ctrl = {stall_pc, stall_if2, stall_if_id, stall_id_ex,
                       flush_if2, flush_if_id, flush_id_ex, flush_ex_mem};
    reg  [7:0] exp_ctrl = 0;
    wire       ok = (ctrl === exp_ctrl);

    localparam NONE = 8'h00, LU = 8'hE2, MUL = 8'hF1, STOP = 8'h8C, BR = 8'h0E;

    // id instruction: rs1, rs2, uses_rs1, uses_rs2, is_store
    // in flight:      load in EX (rd, mem_read), load in MEM1 (rd, mem_read)
    // events:         branch_taken, mult_busy, stop_fetch
    task t(input [7:0] id, input [8*16-1:0] s,
           input [4:0] r1, input [4:0] r2, input u1, input u2, input st,
           input [4:0] exrd, input exld, input [4:0] m1rd, input m1ld,
           input br, input mb, input sf, input [7:0] e);
        begin
            case_id = id; scenario = s;
            id_rs1 = r1; id_rs2 = r2; id_uses_rs1 = u1; id_uses_rs2 = u2; id_is_store = st;
            idex_rd = exrd; idex_mem_read = exld; exmem1_rd = m1rd; exmem1_mem_read = m1ld;
            branch_taken = br; mult_busy = mb; stop_fetch = sf;
            exp_ctrl = e;
            #10;
        end
    endtask

    initial begin
        $dumpfile("waves/tb_hazard.vcd");
        $dumpvars(1, tb_hazard);
        #10;
        //   id  label            rs1 rs2 u1 u2 st  EXrd ld  M1rd ld  br mb sf  expected
        t(1,  "IDLE",            1,  2, 1, 1, 0,   0, 0,    0, 0,  0, 0, 0,  NONE);
        // ld x5 ; add x6, x5, x7   (consumer right behind the load: 2 stall cycles)
        t(2,  "LU_EX_RS1",       5,  7, 1, 1, 0,   5, 1,    0, 0,  0, 0, 0,  LU);   // load in EX
        t(3,  "LU_MEM1_RS1",     5,  7, 1, 1, 0,   0, 0,    5, 1,  0, 0, 0,  LU);   // same load, now in MEM1
        t(4,  "LU_RELEASED",     5,  7, 1, 1, 0,   0, 0,    0, 0,  0, 0, 0,  NONE); // load in MEM2: go
        t(5,  "LU_EX_RS2",       7,  5, 1, 1, 0,   5, 1,    0, 0,  0, 0, 0,  LU);   // ALU rs2 = load rd
        t(6,  "LU_STORE_DATA",   8,  5, 1, 1, 1,   5, 1,    0, 0,  0, 0, 0,  NONE); // sd x5: data forwarded late
        t(7,  "LU_STORE_ADDR",   5,  8, 1, 1, 1,   5, 1,    0, 0,  0, 0, 0,  LU);   // sd x8,0(x5): address needed
        t(8,  "LU_RD_X0",        0,  7, 1, 1, 0,   0, 1,    0, 0,  0, 0, 0,  NONE); // ld x0: no hazard
        t(9,  "LU_NOT_USED",     5,  7, 0, 0, 0,   5, 1,    0, 0,  0, 0, 0,  NONE); // lui: rs fields unused
        t(10, "ALU_IN_EX",       5,  7, 1, 1, 0,   5, 0,    0, 0,  0, 0, 0,  NONE); // not a load: forwarding
        t(11, "BRANCH_TAKEN",    1,  2, 1, 1, 0,   0, 0,    0, 0,  1, 0, 0,  BR);
        t(12, "MULT_BUSY",       1,  2, 1, 1, 0,   0, 0,    0, 0,  0, 1, 0,  MUL);
        t(13, "STOP_FETCH",      1,  2, 1, 1, 0,   0, 0,    0, 0,  0, 0, 1,  STOP);
        t(14, "PRIO_BR_OVER_LU", 5,  7, 1, 1, 0,   5, 1,    0, 0,  1, 0, 0,  BR);
        t(15, "PRIO_MUL_OVER_LU",5,  7, 1, 1, 0,   5, 1,    0, 0,  0, 1, 0,  MUL);
        t(16, "PRIO_STOP_OVR_LU",5,  7, 1, 1, 0,   5, 1,    0, 0,  0, 0, 1,  STOP);
        t(17, "PRIO_BR_OVER_ALL",5,  7, 1, 1, 0,   5, 1,    0, 0,  1, 1, 1,  BR);
        #10;
        $finish;
    end

endmodule
