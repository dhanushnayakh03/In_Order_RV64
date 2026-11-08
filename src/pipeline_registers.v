// ============================================================================
// File: pipeline_registers.v
// Description: Pipeline registers of the 7-stage in-order RV64 core
//                IF1 | IF2 | ID | EX | MEM1 | MEM2 | WB
//              if1_if2_reg, if_id_reg (IF2/ID), id_ex_reg, ex_mem1_reg,
//              mem1_mem2_reg, mem_wb_reg (MEM2/WB)
//   valid_out = 0 marks a bubble (reset / flush / stall bubble).
// Standard Verilog-2001
// ============================================================================

`include "rv64_defs.v"

// ----------------------------------------------------------------------------
// 1. IF1/IF2 Register
//    The instruction itself is held by the IMEM BRAM output register (whose
//    enable follows !stall), so only PC and valid are kept here.
// ----------------------------------------------------------------------------
module if1_if2_reg (
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  stall,
    input  wire                  flush,

    input  wire [`XLEN-1:0]      pc_in,

    output reg  [`XLEN-1:0]      pc_out,
    output reg                   valid_out
);

    always @(posedge clk) begin
        if (rst || flush) begin
            pc_out    <= {`XLEN{1'b0}};
            valid_out <= 1'b0;
        end else if (!stall) begin
            pc_out    <= pc_in;
            valid_out <= 1'b1;
        end
    end

endmodule

// ----------------------------------------------------------------------------
// 2. IF2/ID Register
// ----------------------------------------------------------------------------
module if_id_reg (
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  stall,
    input  wire                  flush,

    input  wire [`XLEN-1:0]      pc_in,
    input  wire [`ILEN-1:0]      inst_in,
    input  wire                  valid_in,

    output reg  [`XLEN-1:0]      pc_out,
    output reg  [`ILEN-1:0]      inst_out,
    output reg                   valid_out
);

    always @(posedge clk) begin
        if (rst || flush) begin
            pc_out    <= {`XLEN{1'b0}};
            inst_out  <= `NOP_INST;
            valid_out <= 1'b0;
        end else if (!stall) begin
            pc_out    <= pc_in;
            inst_out  <= valid_in ? inst_in : `NOP_INST; // bubbles decode as NOP
            valid_out <= valid_in;
        end
    end

endmodule

// ----------------------------------------------------------------------------
// 3. ID/EX Register
// ----------------------------------------------------------------------------
module id_ex_reg (
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  stall,
    input  wire                  flush,

    // Data inputs
    input  wire [`XLEN-1:0]      pc_in,
    input  wire [`XLEN-1:0]      rdata1_in,
    input  wire [`XLEN-1:0]      rdata2_in,
    input  wire [`XLEN-1:0]      imm_in,
    input  wire [4:0]            rs1_in,
    input  wire [4:0]            rs2_in,
    input  wire [4:0]            rd_in,

    // Control inputs
    input  wire [4:0]            alu_ctrl_in,
    input  wire                  alua_sel_in,
    input  wire                  alub_sel_in,
    input  wire                  branch_in,
    input  wire                  jal_in,
    input  wire                  jalr_in,
    input  wire                  mem_read_in,
    input  wire                  mem_write_in,
    input  wire                  reg_write_in,
    input  wire [2:0]            funct3_in,
    input  wire                  halt_in,
    input  wire                  valid_in,
    input  wire                  illegal_in,

    // Data outputs
    output reg  [`XLEN-1:0]      pc_out,
    output reg  [`XLEN-1:0]      rdata1_out,
    output reg  [`XLEN-1:0]      rdata2_out,
    output reg  [`XLEN-1:0]      imm_out,
    output reg  [4:0]            rs1_out,
    output reg  [4:0]            rs2_out,
    output reg  [4:0]            rd_out,

    // Control outputs
    output reg  [4:0]            alu_ctrl_out,
    output reg                   alua_sel_out,
    output reg                   alub_sel_out,
    output reg                   branch_out,
    output reg                   jal_out,
    output reg                   jalr_out,
    output reg                   mem_read_out,
    output reg                   mem_write_out,
    output reg                   reg_write_out,
    output reg  [2:0]            funct3_out,
    output reg                   halt_out,
    output reg                   valid_out,
    output reg                   illegal_out
);

    always @(posedge clk) begin
        if (rst || flush) begin
            pc_out        <= {`XLEN{1'b0}};
            rdata1_out    <= {`XLEN{1'b0}};
            rdata2_out    <= {`XLEN{1'b0}};
            imm_out       <= {`XLEN{1'b0}};
            rs1_out       <= 5'd0;
            rs2_out       <= 5'd0;
            rd_out        <= 5'd0;
            alu_ctrl_out  <= `ALU_ADD;
            alua_sel_out  <= `ALUA_SEL_RS1;
            alub_sel_out  <= `ALUB_SEL_RS2;
            branch_out    <= 1'b0;
            jal_out       <= 1'b0;
            jalr_out      <= 1'b0;
            mem_read_out  <= 1'b0;
            mem_write_out <= 1'b0;
            reg_write_out <= 1'b0;
            funct3_out    <= 3'd0;
            halt_out      <= 1'b0;
            valid_out     <= 1'b0;
            illegal_out   <= 1'b0;
        end else if (!stall) begin
            pc_out        <= pc_in;
            rdata1_out    <= rdata1_in;
            rdata2_out    <= rdata2_in;
            imm_out       <= imm_in;
            rs1_out       <= rs1_in;
            rs2_out       <= rs2_in;
            rd_out        <= rd_in;
            alu_ctrl_out  <= alu_ctrl_in;
            alua_sel_out  <= alua_sel_in;
            alub_sel_out  <= alub_sel_in;
            branch_out    <= branch_in;
            jal_out       <= jal_in;
            jalr_out      <= jalr_in;
            mem_read_out  <= mem_read_in;
            mem_write_out <= mem_write_in;
            reg_write_out <= reg_write_in;
            funct3_out    <= funct3_in;
            halt_out      <= halt_in;
            valid_out     <= valid_in;
            illegal_out   <= illegal_in;
        end
    end

endmodule

// ----------------------------------------------------------------------------
// 4. EX/MEM1 Register
//    result = ALU result / memory address, PC+4 for JAL/JALR,
//             PC of the instruction for illegal instructions (error report)
// ----------------------------------------------------------------------------
module ex_mem1_reg (
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  flush,

    input  wire [`XLEN-1:0]      result_in,
    input  wire [`XLEN-1:0]      store_data_in,
    input  wire [4:0]            rs2_in,
    input  wire [4:0]            rd_in,
    input  wire                  mem_read_in,
    input  wire                  mem_write_in,
    input  wire                  reg_write_in,
    input  wire [2:0]            funct3_in,
    input  wire                  halt_in,
    input  wire                  valid_in,
    input  wire                  illegal_in,

    output reg  [`XLEN-1:0]      result_out,
    output reg  [`XLEN-1:0]      store_data_out,
    output reg  [4:0]            rs2_out,
    output reg  [4:0]            rd_out,
    output reg                   mem_read_out,
    output reg                   mem_write_out,
    output reg                   reg_write_out,
    output reg  [2:0]            funct3_out,
    output reg                   halt_out,
    output reg                   valid_out,
    output reg                   illegal_out
);

    always @(posedge clk) begin
        if (rst || flush) begin
            result_out     <= {`XLEN{1'b0}};
            store_data_out <= {`XLEN{1'b0}};
            rs2_out        <= 5'd0;
            rd_out         <= 5'd0;
            mem_read_out   <= 1'b0;
            mem_write_out  <= 1'b0;
            reg_write_out  <= 1'b0;
            funct3_out     <= 3'd0;
            halt_out       <= 1'b0;
            valid_out      <= 1'b0;
            illegal_out    <= 1'b0;
        end else begin
            result_out     <= result_in;
            store_data_out <= store_data_in;
            rs2_out        <= rs2_in;
            rd_out         <= rd_in;
            mem_read_out   <= mem_read_in;
            mem_write_out  <= mem_write_in;
            reg_write_out  <= reg_write_in;
            funct3_out     <= funct3_in;
            halt_out       <= halt_in;
            valid_out      <= valid_in;
            illegal_out    <= illegal_in;
        end
    end

endmodule

// ----------------------------------------------------------------------------
// 5. MEM1/MEM2 Register (load data itself arrives from the DMEM BRAM)
// ----------------------------------------------------------------------------
module mem1_mem2_reg (
    input  wire                  clk,
    input  wire                  rst,

    input  wire [`XLEN-1:0]      result_in,
    input  wire [4:0]            rd_in,
    input  wire                  mem_read_in,
    input  wire                  reg_write_in,
    input  wire [2:0]            funct3_in,
    input  wire                  halt_in,
    input  wire                  valid_in,
    input  wire                  illegal_in,

    output reg  [`XLEN-1:0]      result_out,
    output reg  [4:0]            rd_out,
    output reg                   mem_read_out,
    output reg                   reg_write_out,
    output reg  [2:0]            funct3_out,
    output reg                   halt_out,
    output reg                   valid_out,
    output reg                   illegal_out
);

    always @(posedge clk) begin
        if (rst) begin
            result_out    <= {`XLEN{1'b0}};
            rd_out        <= 5'd0;
            mem_read_out  <= 1'b0;
            reg_write_out <= 1'b0;
            funct3_out    <= 3'd0;
            halt_out      <= 1'b0;
            valid_out     <= 1'b0;
            illegal_out   <= 1'b0;
        end else begin
            result_out    <= result_in;
            rd_out        <= rd_in;
            mem_read_out  <= mem_read_in;
            reg_write_out <= reg_write_in;
            funct3_out    <= funct3_in;
            halt_out      <= halt_in;
            valid_out     <= valid_in;
            illegal_out   <= illegal_in;
        end
    end

endmodule

// ----------------------------------------------------------------------------
// 6. MEM2/WB Register (final writeback value already selected in MEM2)
// ----------------------------------------------------------------------------
module mem_wb_reg (
    input  wire                  clk,
    input  wire                  rst,

    input  wire [`XLEN-1:0]      result_in,
    input  wire [4:0]            rd_in,
    input  wire                  reg_write_in,
    input  wire                  halt_in,
    input  wire                  valid_in,
    input  wire                  illegal_in,

    output reg  [`XLEN-1:0]      result_out,
    output reg  [4:0]            rd_out,
    output reg                   reg_write_out,
    output reg                   halt_out,
    output reg                   valid_out,
    output reg                   illegal_out
);

    always @(posedge clk) begin
        if (rst) begin
            result_out    <= {`XLEN{1'b0}};
            rd_out        <= 5'd0;
            reg_write_out <= 1'b0;
            halt_out      <= 1'b0;
            valid_out     <= 1'b0;
            illegal_out   <= 1'b0;
        end else begin
            result_out    <= result_in;
            rd_out        <= rd_in;
            reg_write_out <= reg_write_in;
            halt_out      <= halt_in;
            valid_out     <= valid_in;
            illegal_out   <= illegal_in;
        end
    end

endmodule
