// ============================================================================
// File: core_top.v
// Description: 7-stage in-order RV64IM core (no DIV/REM) for synchronous
//              Block RAM instruction and data memories.
//
//   IF1 : PC drives the IMEM address (BRAM samples it at the end of IF1)
//   IF2 : instruction returns from IMEM
//   ID  : decode, register file read (WB write-through), hazard detection
//   EX  : forwarding, ALU / 4-cycle multiplier, branch resolution
//   MEM1: DMEM access (store write / load address), late store-data forward
//   MEM2: load data returns from DMEM, alignment / sign-extension
//   WB  : register file write, commit, halt/error, counters
//
//   Taken branch / jump penalty : 3 cycles (IF1, IF2, ID squashed)
//   Load-use penalty            : 2 cycles (1 if the consumer is 2 behind);
//                                 none when the load result is store data
//   Multiply                    : 4 cycles in EX
//
//   Memory interface timing (both synchronous, BRAM):
//     imem: imem_addr/imem_en sampled at clock edge, imem_rdata valid next cycle
//     dmem: dmem_* sampled at clock edge (writes happen there), dmem_rdata
//           valid next cycle
// Standard Verilog-2001
// ============================================================================

`include "rv64_defs.v"

module core_top (
    input  wire                  clk,
    input  wire                  rst,

    // Instruction Memory Interface (synchronous read)
    output wire [`XLEN-1:0]      imem_addr,
    output wire                  imem_en,
    input  wire [`ILEN-1:0]      imem_rdata,

    // Data Memory Interface (synchronous read / write)
    output wire [`XLEN-1:0]      dmem_addr,
    output wire [`XLEN-1:0]      dmem_wdata,
    output wire [7:0]            dmem_we,            // byte write enables (0 = read)
    output wire                  dmem_en,
    input  wire [`XLEN-1:0]      dmem_rdata,

    // Status & Performance
    output reg                   halted,             // sticky: WFI or illegal instruction reached WB
    output reg                   error,              // sticky: halted because of an illegal/unsupported instruction
    output reg  [`XLEN-1:0]      error_pc,           // PC of the offending instruction (valid when error=1)
    output reg  [31:0]           cycle_count,        // cycles until the halting instruction reaches WB (exclusive)
    output reg  [31:0]           retired_inst_count, // valid instructions committed in WB (incl. WFI, excl. illegal)

    // Debug: read architectural register x[dbg_reg_addr] (combinational)
    input  wire [4:0]            dbg_reg_addr,
    output wire [`XLEN-1:0]      dbg_reg_data
);

    // ========================================================================
    // Hazard / control wires
    // ========================================================================
    wire stall_pc, stall_if2, stall_if_id, stall_id_ex;
    wire flush_if2, flush_if_id, flush_id_ex, flush_ex_mem;
    wire mult_busy;
    wire stop_fetch;
    wire [1:0] forward_a, forward_b;
    wire branch_taken;
    wire [`XLEN-1:0] branch_target;

    // IF1
    wire [`XLEN-1:0] if1_pc;
    wire [`XLEN-1:0] if1_pc_plus_4;

    // IF1/IF2
    wire [`XLEN-1:0] if2_pc;
    wire             if2_valid;

    // IF2/ID
    wire [`XLEN-1:0] if_id_pc;
    wire [`ILEN-1:0] if_id_inst;
    wire             if_id_valid;

    // ID outputs
    wire [4:0]       id_rs1, id_rs2, id_rd;
    wire [`XLEN-1:0] id_rdata1, id_rdata2, id_imm;
    wire             id_uses_rs1, id_uses_rs2;
    wire [4:0]       id_alu_ctrl;
    wire             id_alua_sel, id_alub_sel;
    wire             id_branch, id_jal, id_jalr;
    wire             id_mem_read, id_mem_write, id_reg_write;
    wire [1:0]       id_wb_sel;                     // unused: result selected in EX/MEM2
    wire [2:0]       id_funct3;
    wire             id_halt, id_illegal;
    wire             id_halt_v    = if_id_valid & id_halt;
    wire             id_illegal_v = if_id_valid & id_illegal;

    // ID/EX
    wire [`XLEN-1:0] id_ex_pc, id_ex_rdata1, id_ex_rdata2, id_ex_imm;
    wire [4:0]       id_ex_rs1, id_ex_rs2, id_ex_rd;
    wire [4:0]       id_ex_alu_ctrl;
    wire             id_ex_alua_sel, id_ex_alub_sel;
    wire             id_ex_branch, id_ex_jal, id_ex_jalr;
    wire             id_ex_mem_read, id_ex_mem_write, id_ex_reg_write;
    wire [2:0]       id_ex_funct3;
    wire             id_ex_halt, id_ex_valid, id_ex_illegal;

    // EX outputs
    wire [`XLEN-1:0] ex_alu_result;
    wire [`XLEN-1:0] ex_store_data;
    wire [`XLEN-1:0] ex_result;

    // EX/MEM1
    wire [`XLEN-1:0] ex_mem1_result, ex_mem1_store_data;
    wire [4:0]       ex_mem1_rs2, ex_mem1_rd;
    wire             ex_mem1_mem_read, ex_mem1_mem_write, ex_mem1_reg_write;
    wire [2:0]       ex_mem1_funct3;
    wire             ex_mem1_halt, ex_mem1_valid, ex_mem1_illegal;

    // MEM1/MEM2
    wire [`XLEN-1:0] mem1_mem2_result;
    wire [4:0]       mem1_mem2_rd;
    wire             mem1_mem2_mem_read, mem1_mem2_reg_write;
    wire [2:0]       mem1_mem2_funct3;
    wire             mem1_mem2_halt, mem1_mem2_valid, mem1_mem2_illegal;

    // MEM2 output
    wire [`XLEN-1:0] mem2_wb_value;

    // MEM2/WB
    wire [`XLEN-1:0] mem_wb_result;
    wire [4:0]       mem_wb_rd;
    wire             mem_wb_reg_write;
    wire             mem_wb_halt, mem_wb_valid, mem_wb_illegal;

    wire [`XLEN-1:0] wb_data = mem_wb_result;

    // ========================================================================
    // 1. IF1: PC register -> IMEM address
    // ========================================================================
    if_stage if_inst (
        .clk           (clk),
        .rst           (rst),
        .stall_pc      (stall_pc),
        .branch_taken  (branch_taken),
        .branch_target (branch_target),
        .imem_addr     (imem_addr),
        .pc            (if1_pc),
        .pc_plus_4     (if1_pc_plus_4)
    );

    // IMEM output register advances together with IF1/IF2
    assign imem_en = !stall_if2;

    if1_if2_reg if1_if2_reg_inst (
        .clk       (clk),
        .rst       (rst),
        .stall     (stall_if2),
        .flush     (flush_if2),
        .pc_in     (if1_pc),
        .pc_out    (if2_pc),
        .valid_out (if2_valid)
    );

    // ========================================================================
    // 2. IF2: instruction from IMEM -> IF2/ID
    // ========================================================================
    if_id_reg if_id_reg_inst (
        .clk       (clk),
        .rst       (rst),
        .stall     (stall_if_id),
        .flush     (flush_if_id),
        .pc_in     (if2_pc),
        .inst_in   (imem_rdata),
        .valid_in  (if2_valid),
        .pc_out    (if_id_pc),
        .inst_out  (if_id_inst),
        .valid_out (if_id_valid)
    );

    // ========================================================================
    // 3. ID
    // ========================================================================
    id_stage id_inst (
        .clk       (clk),
        .rst       (rst),
        .inst      (if_id_inst),
        .pc        (if_id_pc),
        .wb_wen    (mem_wb_reg_write),
        .wb_waddr  (mem_wb_rd),
        .wb_wdata  (wb_data),
        .dbg_raddr (dbg_reg_addr),
        .dbg_rdata (dbg_reg_data),
        .rs1       (id_rs1),
        .rs2       (id_rs2),
        .rd        (id_rd),
        .rdata1    (id_rdata1),
        .rdata2    (id_rdata2),
        .imm       (id_imm),
        .uses_rs1  (id_uses_rs1),
        .uses_rs2  (id_uses_rs2),
        .alu_ctrl  (id_alu_ctrl),
        .alua_sel  (id_alua_sel),
        .alub_sel  (id_alub_sel),
        .branch    (id_branch),
        .jal       (id_jal),
        .jalr      (id_jalr),
        .mem_read  (id_mem_read),
        .mem_write (id_mem_write),
        .reg_write (id_reg_write),
        .wb_sel    (id_wb_sel),
        .funct3    (id_funct3),
        .halt      (id_halt),
        .illegal   (id_illegal)
    );

    id_ex_reg id_ex_reg_inst (
        .clk           (clk),
        .rst           (rst),
        .stall         (stall_id_ex),
        .flush         (flush_id_ex),
        .pc_in         (if_id_pc),
        .rdata1_in     (id_rdata1),
        .rdata2_in     (id_rdata2),
        .imm_in        (id_imm),
        .rs1_in        (id_rs1),
        .rs2_in        (id_rs2),
        .rd_in         (id_rd),
        .alu_ctrl_in   (id_alu_ctrl),
        .alua_sel_in   (id_alua_sel),
        .alub_sel_in   (id_alub_sel),
        .branch_in     (id_branch),
        .jal_in        (id_jal),
        .jalr_in       (id_jalr),
        .mem_read_in   (id_mem_read),
        .mem_write_in  (id_mem_write),
        .reg_write_in  (id_reg_write),
        .funct3_in     (id_funct3),
        .halt_in       (id_halt_v),
        .valid_in      (if_id_valid),
        .illegal_in    (id_illegal_v),
        .pc_out        (id_ex_pc),
        .rdata1_out    (id_ex_rdata1),
        .rdata2_out    (id_ex_rdata2),
        .imm_out       (id_ex_imm),
        .rs1_out       (id_ex_rs1),
        .rs2_out       (id_ex_rs2),
        .rd_out        (id_ex_rd),
        .alu_ctrl_out  (id_ex_alu_ctrl),
        .alua_sel_out  (id_ex_alua_sel),
        .alub_sel_out  (id_ex_alub_sel),
        .branch_out    (id_ex_branch),
        .jal_out       (id_ex_jal),
        .jalr_out      (id_ex_jalr),
        .mem_read_out  (id_ex_mem_read),
        .mem_write_out (id_ex_mem_write),
        .reg_write_out (id_ex_reg_write),
        .funct3_out    (id_ex_funct3),
        .halt_out      (id_ex_halt),
        .valid_out     (id_ex_valid),
        .illegal_out   (id_ex_illegal)
    );

    // ========================================================================
    // 4. Hazard Detection & Forwarding
    // ========================================================================
    // A WFI / illegal instruction in ID can only be removed by an older taken
    // branch in EX (higher priority in the hazard unit). Past ID it is
    // non-speculative, so fetch stays stopped until reset.
    assign stop_fetch = id_halt_v      | id_illegal_v      |
                        id_ex_halt     | id_ex_illegal     |
                        ex_mem1_halt   | ex_mem1_illegal   |
                        mem1_mem2_halt | mem1_mem2_illegal |
                        mem_wb_halt    | mem_wb_illegal    |
                        halted;

    hazard_detection hazard_unit (
        .if_id_rs1        (id_rs1),
        .if_id_rs2        (id_rs2),
        .if_id_uses_rs1   (id_uses_rs1),
        .if_id_uses_rs2   (id_uses_rs2),
        .if_id_is_store   (id_mem_write),
        .id_ex_rd         (id_ex_rd),
        .id_ex_mem_read   (id_ex_mem_read),
        .ex_mem1_rd       (ex_mem1_rd),
        .ex_mem1_mem_read (ex_mem1_mem_read),
        .branch_taken     (branch_taken),
        .mult_busy        (mult_busy),
        .stop_fetch       (stop_fetch),
        .stall_pc         (stall_pc),
        .stall_if2        (stall_if2),
        .stall_if_id      (stall_if_id),
        .stall_id_ex      (stall_id_ex),
        .flush_if2        (flush_if2),
        .flush_if_id      (flush_if_id),
        .flush_id_ex      (flush_id_ex),
        .flush_ex_mem     (flush_ex_mem)
    );

    forwarding_unit fwd_unit (
        .id_ex_rs1           (id_ex_rs1),
        .id_ex_rs2           (id_ex_rs2),
        .ex_mem1_rd          (ex_mem1_rd),
        .ex_mem1_reg_write   (ex_mem1_reg_write),
        .mem1_mem2_rd        (mem1_mem2_rd),
        .mem1_mem2_reg_write (mem1_mem2_reg_write),
        .mem_wb_rd           (mem_wb_rd),
        .mem_wb_reg_write    (mem_wb_reg_write),
        .forward_a           (forward_a),
        .forward_b           (forward_b)
    );

    // ========================================================================
    // 5. EX
    // ========================================================================
    ex_stage ex_inst (
        .clk           (clk),
        .rst           (rst),
        .pc            (id_ex_pc),
        .rdata1        (id_ex_rdata1),
        .rdata2        (id_ex_rdata2),
        .imm           (id_ex_imm),
        .alu_ctrl      (id_ex_alu_ctrl),
        .alua_sel      (id_ex_alua_sel),
        .alub_sel      (id_ex_alub_sel),
        .branch        (id_ex_branch),
        .jal           (id_ex_jal),
        .jalr          (id_ex_jalr),
        .funct3        (id_ex_funct3),
        .forward_a     (forward_a),
        .forward_b     (forward_b),
        .fwd_data_mem1 (ex_mem1_result),
        .fwd_data_mem2 (mem1_mem2_result),
        .fwd_data_wb   (mem_wb_result),
        .alu_result    (ex_alu_result),
        .store_data    (ex_store_data),
        .branch_taken  (branch_taken),
        .branch_target (branch_target),
        .mult_busy     (mult_busy)
    );

    // Single result field carried down the pipe:
    //   JAL/JALR -> link address, illegal -> its PC (error report), else ALU
    assign ex_result = id_ex_illegal               ? id_ex_pc :
                       (id_ex_jal || id_ex_jalr)   ? (id_ex_pc + 64'd4) :
                                                     ex_alu_result;

    ex_mem1_reg ex_mem1_reg_inst (
        .clk            (clk),
        .rst            (rst),
        .flush          (flush_ex_mem),
        .result_in      (ex_result),
        .store_data_in  (ex_store_data),
        .rs2_in         (id_ex_rs2),
        .rd_in          (id_ex_rd),
        .mem_read_in    (id_ex_mem_read),
        .mem_write_in   (id_ex_mem_write),
        .reg_write_in   (id_ex_reg_write),
        .funct3_in      (id_ex_funct3),
        .halt_in        (id_ex_halt),
        .valid_in       (id_ex_valid),
        .illegal_in     (id_ex_illegal),
        .result_out     (ex_mem1_result),
        .store_data_out (ex_mem1_store_data),
        .rs2_out        (ex_mem1_rs2),
        .rd_out         (ex_mem1_rd),
        .mem_read_out   (ex_mem1_mem_read),
        .mem_write_out  (ex_mem1_mem_write),
        .reg_write_out  (ex_mem1_reg_write),
        .funct3_out     (ex_mem1_funct3),
        .halt_out       (ex_mem1_halt),
        .valid_out      (ex_mem1_valid),
        .illegal_out    (ex_mem1_illegal)
    );

    // ========================================================================
    // 6. MEM1: DMEM access
    // ========================================================================
    mem1_stage mem1_inst (
        .addr           (ex_mem1_result),
        .store_data     (ex_mem1_store_data),
        .rs2            (ex_mem1_rs2),
        .funct3         (ex_mem1_funct3),
        .mem_read       (ex_mem1_mem_read),
        .mem_write      (ex_mem1_mem_write),
        .mem2_reg_write (mem1_mem2_reg_write),
        .mem2_rd        (mem1_mem2_rd),
        .mem2_result    (mem2_wb_value),
        .wb_reg_write   (mem_wb_reg_write),
        .wb_rd          (mem_wb_rd),
        .wb_data        (wb_data),
        .dmem_en        (dmem_en),
        .dmem_we        (dmem_we),
        .dmem_addr      (dmem_addr),
        .dmem_wdata     (dmem_wdata)
    );

    mem1_mem2_reg mem1_mem2_reg_inst (
        .clk           (clk),
        .rst           (rst),
        .result_in     (ex_mem1_result),
        .rd_in         (ex_mem1_rd),
        .mem_read_in   (ex_mem1_mem_read),
        .reg_write_in  (ex_mem1_reg_write),
        .funct3_in     (ex_mem1_funct3),
        .halt_in       (ex_mem1_halt),
        .valid_in      (ex_mem1_valid),
        .illegal_in    (ex_mem1_illegal),
        .result_out    (mem1_mem2_result),
        .rd_out        (mem1_mem2_rd),
        .mem_read_out  (mem1_mem2_mem_read),
        .reg_write_out (mem1_mem2_reg_write),
        .funct3_out    (mem1_mem2_funct3),
        .halt_out      (mem1_mem2_halt),
        .valid_out     (mem1_mem2_valid),
        .illegal_out   (mem1_mem2_illegal)
    );

    // ========================================================================
    // 7. MEM2: load data alignment, final value select
    // ========================================================================
    mem2_stage mem2_inst (
        .result     (mem1_mem2_result),
        .funct3     (mem1_mem2_funct3),
        .mem_read   (mem1_mem2_mem_read),
        .dmem_rdata (dmem_rdata),
        .wb_value   (mem2_wb_value)
    );

    mem_wb_reg mem_wb_reg_inst (
        .clk           (clk),
        .rst           (rst),
        .result_in     (mem2_wb_value),
        .rd_in         (mem1_mem2_rd),
        .reg_write_in  (mem1_mem2_reg_write),
        .halt_in       (mem1_mem2_halt),
        .valid_in      (mem1_mem2_valid),
        .illegal_in    (mem1_mem2_illegal),
        .result_out    (mem_wb_result),
        .rd_out        (mem_wb_rd),
        .reg_write_out (mem_wb_reg_write),
        .halt_out      (mem_wb_halt),
        .valid_out     (mem_wb_valid),
        .illegal_out   (mem_wb_illegal)
    );

    // ========================================================================
    // 8. WB: commit, halt / error, performance counters
    //    (register file write happens inside id_stage via wb_* ports)
    // ========================================================================
    wire wb_halting = mem_wb_valid & (mem_wb_halt | mem_wb_illegal);

    always @(posedge clk) begin
        if (rst) begin
            halted             <= 1'b0;
            error              <= 1'b0;
            error_pc           <= {`XLEN{1'b0}};
            cycle_count        <= 32'd0;
            retired_inst_count <= 32'd0;
        end else if (!halted) begin
            if (wb_halting) begin
                halted <= 1'b1;
                if (mem_wb_illegal) begin
                    error    <= 1'b1;
                    error_pc <= mem_wb_result;   // illegal carries its PC
                end
            end else begin
                cycle_count <= cycle_count + 32'd1;
            end
            if (mem_wb_valid && !mem_wb_illegal) begin
                retired_inst_count <= retired_inst_count + 32'd1;
            end
        end
    end

endmodule
