// ============================================================================
// File: pipeline_registers.v
// Description: IF/ID, ID/EX, EX/MEM, and MEM/WB pipeline registers
// Standard Verilog-2001
// ============================================================================

`include "rv64_defs.v"

// ----------------------------------------------------------------------------
// 1. IF/ID Pipeline Register
// ----------------------------------------------------------------------------
module if_id_reg (
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  stall,
    input  wire                  flush,

    input  wire [`XLEN-1:0]      pc_in,
    input  wire [`XLEN-1:0]      pc_plus_4_in,
    input  wire [`ILEN-1:0]      inst_in,

    output reg  [`XLEN-1:0]      pc_out,
    output reg  [`XLEN-1:0]      pc_plus_4_out,
    output reg  [`ILEN-1:0]      inst_out
);

    always @(posedge clk) begin
        if (rst || flush) begin
            pc_out        <= {`XLEN{1'b0}};
            pc_plus_4_out <= {`XLEN{1'b0}};
            inst_out      <= `NOP_INST; // Insert NOP on flush or reset
        end else if (!stall) begin
            pc_out        <= pc_in;
            pc_plus_4_out <= pc_plus_4_in;
            inst_out      <= inst_in;
        end
    end

endmodule

// ----------------------------------------------------------------------------
// 2. ID/EX Pipeline Register
// ----------------------------------------------------------------------------
module id_ex_reg (
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  flush,

    // Data inputs
    input  wire [`XLEN-1:0]      pc_in,
    input  wire [`XLEN-1:0]      pc_plus_4_in,
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
    input  wire [1:0]            wb_sel_in,
    input  wire [2:0]            funct3_in,
    input  wire                  halt_in,

    // Data outputs
    output reg  [`XLEN-1:0]      pc_out,
    output reg  [`XLEN-1:0]      pc_plus_4_out,
    output reg  [`XLEN-1:0]      rdata1_out,
    output reg  [`XLEN-1:0]      rdata2_out,
    output reg  [`XLEN-1:0]      imm_out,
    output reg  [4:0]            rs1_out,
    output reg  [4:0]            rs2_out,
    output reg  [4:0]            rd_out,

    // Control outputs
    output reg  [4:0]            alu_ctrl_out,
    output reg                  alua_sel_out,
    output reg                  alub_sel_out,
    output reg                  branch_out,
    output reg                  jal_out,
    output reg                  jalr_out,
    output reg                  mem_read_out,
    output reg                  mem_write_out,
    output reg                  reg_write_out,
    output reg  [1:0]            wb_sel_out,
    output reg  [2:0]            funct3_out,
    output reg                  halt_out
);

    always @(posedge clk) begin
        if (rst || flush) begin
            pc_out        <= {`XLEN{1'b0}};
            pc_plus_4_out <= {`XLEN{1'b0}};
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
            wb_sel_out    <= `WB_SEL_ALU;
            funct3_out    <= 3'd0;
            halt_out      <= 1'b0;
        end else begin
            pc_out        <= pc_in;
            pc_plus_4_out <= pc_plus_4_in;
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
            wb_sel_out    <= wb_sel_in;
            funct3_out    <= funct3_in;
            halt_out      <= halt_in;
        end
    end

endmodule

// ----------------------------------------------------------------------------
// 3. EX/MEM Pipeline Register
// ----------------------------------------------------------------------------
module ex_mem_reg (
    input  wire                  clk,
    input  wire                  rst,

    // Data inputs
    input  wire [`XLEN-1:0]      alu_result_in,
    input  wire [`XLEN-1:0]      store_data_in,
    input  wire [4:0]            rd_in,
    input  wire [`XLEN-1:0]      pc_plus_4_in,

    // Control inputs
    input  wire                  mem_read_in,
    input  wire                  mem_write_in,
    input  wire                  reg_write_in,
    input  wire [1:0]            wb_sel_in,
    input  wire [2:0]            funct3_in,
    input  wire                  halt_in,

    // Data outputs
    output reg  [`XLEN-1:0]      alu_result_out,
    output reg  [`XLEN-1:0]      store_data_out,
    output reg  [4:0]            rd_out,
    output reg  [`XLEN-1:0]      pc_plus_4_out,

    // Control outputs
    output reg                  mem_read_out,
    output reg                  mem_write_out,
    output reg                  reg_write_out,
    output reg  [1:0]            wb_sel_out,
    output reg  [2:0]            funct3_out,
    output reg                  halt_out
);

    always @(posedge clk) begin
        if (rst) begin
            alu_result_out <= {`XLEN{1'b0}};
            store_data_out <= {`XLEN{1'b0}};
            rd_out         <= 5'd0;
            pc_plus_4_out  <= {`XLEN{1'b0}};

            mem_read_out   <= 1'b0;
            mem_write_out  <= 1'b0;
            reg_write_out  <= 1'b0;
            wb_sel_out     <= `WB_SEL_ALU;
            funct3_out     <= 3'd0;
            halt_out       <= 1'b0;
        end else begin
            alu_result_out <= alu_result_in;
            store_data_out <= store_data_in;
            rd_out         <= rd_in;
            pc_plus_4_out  <= pc_plus_4_in;

            mem_read_out   <= mem_read_in;
            mem_write_out  <= mem_write_in;
            reg_write_out  <= reg_write_in;
            wb_sel_out     <= wb_sel_in;
            funct3_out     <= funct3_in;
            halt_out       <= halt_in;
        end
    end

endmodule

// ----------------------------------------------------------------------------
// 4. MEM/WB Pipeline Register
// ----------------------------------------------------------------------------
module mem_wb_reg (
    input  wire                  clk,
    input  wire                  rst,

    // Data inputs
    input  wire [`XLEN-1:0]      alu_result_in,
    input  wire [`XLEN-1:0]      load_data_in,
    input  wire [4:0]            rd_in,
    input  wire [`XLEN-1:0]      pc_plus_4_in,

    // Control inputs
    input  wire                  reg_write_in,
    input  wire [1:0]            wb_sel_in,
    input  wire                  halt_in,

    // Data outputs
    output reg  [`XLEN-1:0]      alu_result_out,
    output reg  [`XLEN-1:0]      load_data_out,
    output reg  [4:0]            rd_out,
    output reg  [`XLEN-1:0]      pc_plus_4_out,

    // Control outputs
    output reg                  reg_write_out,
    output reg  [1:0]            wb_sel_out,
    output reg                  halt_out
);

    always @(posedge clk) begin
        if (rst) begin
            alu_result_out <= {`XLEN{1'b0}};
            load_data_out  <= {`XLEN{1'b0}};
            rd_out         <= 5'd0;
            pc_plus_4_out  <= {`XLEN{1'b0}};

            reg_write_out  <= 1'b0;
            wb_sel_out     <= `WB_SEL_ALU;
            halt_out       <= 1'b0;
        end else begin
            alu_result_out <= alu_result_in;
            load_data_out  <= load_data_in;
            rd_out         <= rd_in;
            pc_plus_4_out  <= pc_plus_4_in;

            reg_write_out  <= reg_write_in;
            wb_sel_out     <= wb_sel_in;
            halt_out       <= halt_in;
        end
    end

endmodule
