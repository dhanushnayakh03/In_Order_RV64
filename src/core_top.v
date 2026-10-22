// ============================================================================
// File: core_top.v
// Description: Top-level 5-stage In-Order RV64I Pipelined Processor Core
// Standard Verilog-2001
// ============================================================================

`include "rv64_defs.v"

module core_top (
    input  wire                  clk,
    input  wire                  rst,

    // Instruction Memory Interface (Read-only, 32-bit instructions)
    output wire [`XLEN-1:0]      imem_addr,
    input  wire [`ILEN-1:0]      imem_rdata,

    // Data Memory Interface (Read/Write, 64-bit doublewords)
    output wire [`XLEN-1:0]      dmem_addr,
    output wire [`XLEN-1:0]      dmem_wdata,
    output wire [7:0]            dmem_byte_en,
    output wire                  dmem_en,
    output wire                  dmem_wen,
    input  wire [`XLEN-1:0]      dmem_rdata,

    // Performance & Status outputs
    output wire                  halted,
    output reg  [31:0]           cycle_count,
    output reg  [31:0]           retired_inst_count
);

    // ========================================================================
    // Internal Wires & Interconnects
    // ========================================================================

    // Hazard Detection Signals
    wire stall_pc;
    wire stall_if_id;
    wire flush_if_id;
    wire flush_id_ex;

    // Forwarding Signals
    wire [1:0] forward_a;
    wire [1:0] forward_b;

    // Branch / Jump Signals from EX
    wire                  branch_taken;
    wire [`XLEN-1:0]      branch_target;

    // IF Stage Outputs
    wire [`XLEN-1:0]      if_pc;
    wire [`XLEN-1:0]      if_pc_plus_4;

    // IF/ID Register Outputs
    wire [`XLEN-1:0]      if_id_pc;
    wire [`XLEN-1:0]      if_id_pc_plus_4;
    wire [`ILEN-1:0]      if_id_inst;

    // ID Stage Outputs
    wire [4:0]            id_rs1;
    wire [4:0]            id_rs2;
    wire [4:0]            id_rd;
    wire [`XLEN-1:0]      id_rdata1;
    wire [`XLEN-1:0]      id_rdata2;
    wire [`XLEN-1:0]      id_imm;
    wire                  id_uses_rs1;
    wire                  id_uses_rs2;
    wire [4:0]            id_alu_ctrl;
    wire                  id_alua_sel;
    wire                  id_alub_sel;
    wire                  id_branch;
    wire                  id_jal;
    wire                  id_jalr;
    wire                  id_mem_read;
    wire                  id_mem_write;
    wire                  id_reg_write;
    wire [1:0]            id_wb_sel;
    wire [2:0]            id_funct3;
    wire                  id_halt;

    // ID/EX Register Outputs
    wire [`XLEN-1:0]      id_ex_pc;
    wire [`XLEN-1:0]      id_ex_pc_plus_4;
    wire [`XLEN-1:0]      id_ex_rdata1;
    wire [`XLEN-1:0]      id_ex_rdata2;
    wire [`XLEN-1:0]      id_ex_imm;
    wire [4:0]            id_ex_rs1;
    wire [4:0]            id_ex_rs2;
    wire [4:0]            id_ex_rd;
    wire [4:0]            id_ex_alu_ctrl;
    wire                  id_ex_alua_sel;
    wire                  id_ex_alub_sel;
    wire                  id_ex_branch;
    wire                  id_ex_jal;
    wire                  id_ex_jalr;
    wire                  id_ex_mem_read;
    wire                  id_ex_mem_write;
    wire                  id_ex_reg_write;
    wire [1:0]            id_ex_wb_sel;
    wire [2:0]            id_ex_funct3;
    wire                  id_ex_halt;

    // EX Stage Outputs
    wire [`XLEN-1:0]      ex_alu_result;
    wire [`XLEN-1:0]      ex_store_data;

    // EX/MEM Register Outputs
    wire [`XLEN-1:0]      ex_mem_alu_result;
    wire [`XLEN-1:0]      ex_mem_store_data;
    wire [4:0]            ex_mem_rd;
    wire [`XLEN-1:0]      ex_mem_pc_plus_4;
    wire                  ex_mem_mem_read;
    wire                  ex_mem_mem_write;
    wire                  ex_mem_reg_write;
    wire [1:0]            ex_mem_wb_sel;
    wire [2:0]            ex_mem_funct3;
    wire                  ex_mem_halt;

    // MEM Stage Outputs
    wire [`XLEN-1:0]      mem_load_data;

    // MEM/WB Register Outputs
    wire [`XLEN-1:0]      mem_wb_alu_result;
    wire [`XLEN-1:0]      mem_wb_load_data;
    wire [4:0]            mem_wb_rd;
    wire [`XLEN-1:0]      mem_wb_pc_plus_4;
    wire                  mem_wb_reg_write;
    wire [1:0]            mem_wb_wb_sel;
    wire                  mem_wb_halt;

    // WB Stage Output
    wire [`XLEN-1:0]      wb_data;

    // ========================================================================
    // 1. Instruction Fetch (IF) Stage & Pipeline Register
    // ========================================================================
    if_stage if_inst (
        .clk           (clk),
        .rst           (rst),
        .stall_pc      (stall_pc),
        .branch_taken  (branch_taken),
        .branch_target (branch_target),
        .imem_addr     (imem_addr),
        .pc            (if_pc),
        .pc_plus_4     (if_pc_plus_4)
    );

    if_id_reg if_id_reg_inst (
        .clk           (clk),
        .rst           (rst),
        .stall         (stall_if_id),
        .flush         (flush_if_id),
        .pc_in         (if_pc),
        .pc_plus_4_in  (if_pc_plus_4),
        .inst_in       (imem_rdata),
        .pc_out        (if_id_pc),
        .pc_plus_4_out (if_id_pc_plus_4),
        .inst_out      (if_id_inst)
    );

    // ========================================================================
    // 2. Instruction Decode (ID) Stage & Pipeline Register
    // ========================================================================
    id_stage id_inst (
        .clk           (clk),
        .rst           (rst),
        .inst          (if_id_inst),
        .pc            (if_id_pc),
        .wb_wen        (mem_wb_reg_write),
        .wb_waddr      (mem_wb_rd),
        .wb_wdata      (wb_data),
        .rs1           (id_rs1),
        .rs2           (id_rs2),
        .rd            (id_rd),
        .rdata1        (id_rdata1),
        .rdata2        (id_rdata2),
        .imm           (id_imm),
        .uses_rs1      (id_uses_rs1),
        .uses_rs2      (id_uses_rs2),
        .alu_ctrl      (id_alu_ctrl),
        .alua_sel      (id_alua_sel),
        .alub_sel      (id_alub_sel),
        .branch        (id_branch),
        .jal           (id_jal),
        .jalr          (id_jalr),
        .mem_read      (id_mem_read),
        .mem_write     (id_mem_write),
        .reg_write     (id_reg_write),
        .wb_sel        (id_wb_sel),
        .funct3        (id_funct3),
        .halt          (id_halt)
    );

    id_ex_reg id_ex_reg_inst (
        .clk           (clk),
        .rst           (rst),
        .flush         (flush_id_ex),
        .pc_in         (if_id_pc),
        .pc_plus_4_in  (if_id_pc_plus_4),
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
        .wb_sel_in     (id_wb_sel),
        .funct3_in     (id_funct3),
        .halt_in       (id_halt),
        .pc_out        (id_ex_pc),
        .pc_plus_4_out (id_ex_pc_plus_4),
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
        .wb_sel_out    (id_ex_wb_sel),
        .funct3_out    (id_ex_funct3),
        .halt_out      (id_ex_halt)
    );

    // ========================================================================
    // 3. Hazard Detection & Forwarding Units
    // ========================================================================
    hazard_detection hazard_unit (
        .if_id_rs1      (id_rs1),
        .if_id_rs2      (id_rs2),
        .if_id_uses_rs1 (id_uses_rs1),
        .if_id_uses_rs2 (id_uses_rs2),
        .id_ex_rd       (id_ex_rd),
        .id_ex_mem_read (id_ex_mem_read),
        .branch_taken   (branch_taken),
        .stall_pc       (stall_pc),
        .stall_if_id    (stall_if_id),
        .flush_if_id    (flush_if_id),
        .flush_id_ex    (flush_id_ex)
    );

    forwarding_unit fwd_unit (
        .id_ex_rs1        (id_ex_rs1),
        .id_ex_rs2        (id_ex_rs2),
        .ex_mem_rd        (ex_mem_rd),
        .ex_mem_reg_write (ex_mem_reg_write),
        .mem_wb_rd        (mem_wb_rd),
        .mem_wb_reg_write (mem_wb_reg_write),
        .forward_a        (forward_a),
        .forward_b        (forward_b)
    );

    // ========================================================================
    // 4. Execution (EX) Stage & Pipeline Register
    // ========================================================================
    ex_stage ex_inst (
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
        .fwd_data_ex   (ex_mem_alu_result),
        .fwd_data_mem  (wb_data),
        .alu_result    (ex_alu_result),
        .store_data    (ex_store_data),
        .branch_taken  (branch_taken),
        .branch_target (branch_target)
    );

    ex_mem_reg ex_mem_reg_inst (
        .clk            (clk),
        .rst            (rst),
        .alu_result_in  (ex_alu_result),
        .store_data_in  (ex_store_data),
        .rd_in          (id_ex_rd),
        .pc_plus_4_in   (id_ex_pc_plus_4),
        .mem_read_in    (id_ex_mem_read),
        .mem_write_in   (id_ex_mem_write),
        .reg_write_in   (id_ex_reg_write),
        .wb_sel_in      (id_ex_wb_sel),
        .funct3_in      (id_ex_funct3),
        .halt_in        (id_ex_halt),
        .alu_result_out (ex_mem_alu_result),
        .store_data_out (ex_mem_store_data),
        .rd_out         (ex_mem_rd),
        .pc_plus_4_out  (ex_mem_pc_plus_4),
        .mem_read_out   (ex_mem_mem_read),
        .mem_write_out  (ex_mem_mem_write),
        .reg_write_out  (ex_mem_reg_write),
        .wb_sel_out     (ex_mem_wb_sel),
        .funct3_out     (ex_mem_funct3),
        .halt_out       (ex_mem_halt)
    );

    // ========================================================================
    // 5. Memory Access (MEM) Stage & Pipeline Register
    // ========================================================================
    mem_stage mem_inst (
        .alu_result   (ex_mem_alu_result),
        .store_data   (ex_mem_store_data),
        .funct3       (ex_mem_funct3),
        .mem_read     (ex_mem_mem_read),
        .mem_write    (ex_mem_mem_write),
        .dmem_addr    (dmem_addr),
        .dmem_wdata   (dmem_wdata),
        .dmem_byte_en (dmem_byte_en),
        .dmem_en      (dmem_en),
        .dmem_wen     (dmem_wen),
        .dmem_rdata   (dmem_rdata),
        .load_data    (mem_load_data)
    );

    mem_wb_reg mem_wb_reg_inst (
        .clk            (clk),
        .rst            (rst),
        .alu_result_in  (ex_mem_alu_result),
        .load_data_in   (mem_load_data),
        .rd_in          (ex_mem_rd),
        .pc_plus_4_in   (ex_mem_pc_plus_4),
        .reg_write_in   (ex_mem_reg_write),
        .wb_sel_in      (ex_mem_wb_sel),
        .halt_in        (ex_mem_halt),
        .alu_result_out (mem_wb_alu_result),
        .load_data_out  (mem_wb_load_data),
        .rd_out         (mem_wb_rd),
        .pc_plus_4_out  (mem_wb_pc_plus_4),
        .reg_write_out  (mem_wb_reg_write),
        .wb_sel_out     (mem_wb_wb_sel),
        .halt_out       (mem_wb_halt)
    );

    // ========================================================================
    // 6. Writeback (WB) Stage
    // ========================================================================
    wb_stage wb_inst (
        .alu_result (mem_wb_alu_result),
        .load_data  (mem_wb_load_data),
        .pc_plus_4  (mem_wb_pc_plus_4),
        .wb_sel     (mem_wb_wb_sel),
        .wb_data    (wb_data)
    );

    // Halt signal when WFI reaches WB stage
    assign halted = mem_wb_halt;

    // Performance Counters
    always @(posedge clk) begin
        if (rst) begin
            cycle_count        <= 32'd0;
            retired_inst_count <= 32'd0;
        end else if (!halted) begin
            cycle_count <= cycle_count + 32'd1;
            // Increment retired instruction count if instruction committed in WB stage
            if (mem_wb_reg_write || mem_wb_halt || (mem_wb_rd == 5'd0)) begin
                retired_inst_count <= retired_inst_count + 32'd1;
            end
        end
    end

endmodule
