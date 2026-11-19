// ============================================================================
// File: mem_stage.v
// Description: Memory stages of the 7-stage pipeline
//   mem1_stage: drives the DMEM BRAM from the EX/MEM1 register (address,
//               byte enables, aligned store data). Stores write at the end of
//               MEM1, loads issue their read here.
//   mem2_stage: load data returns from the BRAM; extract / sign-extend and
//               select the final writeback value for the MEM2/WB register.
// Standard Verilog-2001
// ============================================================================

`include "rv64_defs.v"

// ----------------------------------------------------------------------------
// MEM1
// ----------------------------------------------------------------------------
module mem1_stage (
    // From EX/MEM1 register
    input  wire [`XLEN-1:0]      addr,          // EX/MEM1 result (effective address)
    input  wire [`XLEN-1:0]      store_data,    // rs2 value forwarded in EX
    input  wire [4:0]            rs2,
    input  wire [2:0]            funct3,
    input  wire                  mem_read,
    input  wire                  mem_write,

    // Late store-data forwarding (producer now in MEM2 / WB). Needed when the
    // producer is a load that was not finished when the store was in EX, and
    // always correct otherwise (MEM2 holds the youngest older instruction).
    input  wire                  mem2_reg_write,
    input  wire [4:0]            mem2_rd,
    input  wire [`XLEN-1:0]      mem2_result,   // MEM2 final value (incl. load data)
    input  wire                  wb_reg_write,
    input  wire [4:0]            wb_rd,
    input  wire [`XLEN-1:0]      wb_data,

    // DMEM port A
    output wire                  dmem_en,
    output reg  [7:0]            dmem_we,
    output wire [`XLEN-1:0]      dmem_addr,
    output reg  [`XLEN-1:0]      dmem_wdata
);

    wire [2:0] offset = addr[2:0];

    wire fwd_mem2 = mem2_reg_write && (mem2_rd != 5'd0) && (mem2_rd == rs2);
    wire fwd_wb   = wb_reg_write   && (wb_rd   != 5'd0) && (wb_rd   == rs2);

    wire [`XLEN-1:0] sdata = fwd_mem2 ? mem2_result :
                             fwd_wb   ? wb_data     : store_data;

    assign dmem_addr = addr;
    assign dmem_en   = mem_read | mem_write;

    // Store formatting: byte enables and data alignment
    always @(*) begin
        dmem_we    = 8'b00000000;
        dmem_wdata = {`XLEN{1'b0}};
        if (mem_write) begin
            case (funct3)
                `FUNCT3_SB: begin
                    dmem_we    = 8'b00000001 << offset;
                    dmem_wdata = {8{sdata[7:0]}};
                end
                `FUNCT3_SH: begin
                    dmem_we    = 8'b00000011 << {offset[2:1], 1'b0};
                    dmem_wdata = {4{sdata[15:0]}};
                end
                `FUNCT3_SW: begin
                    dmem_we    = offset[2] ? 8'b11110000 : 8'b00001111;
                    dmem_wdata = {2{sdata[31:0]}};
                end
                `FUNCT3_SD: begin
                    dmem_we    = 8'b11111111;
                    dmem_wdata = sdata;
                end
                default: begin
                    dmem_we    = 8'b00000000;
                    dmem_wdata = {`XLEN{1'b0}};
                end
            endcase
        end
    end

endmodule

// ----------------------------------------------------------------------------
// MEM2
// ----------------------------------------------------------------------------
module mem2_stage (
    // From MEM1/MEM2 register
    input  wire [`XLEN-1:0]      result,        // ALU result / address / PC+4
    input  wire [2:0]            funct3,
    input  wire                  mem_read,

    // From DMEM port A (registered BRAM output)
    input  wire [`XLEN-1:0]      dmem_rdata,

    // Final writeback value
    output wire [`XLEN-1:0]      wb_value
);

    wire [2:0] offset = result[2:0];

    reg [7:0]       selected_byte;
    reg [15:0]      selected_half;
    reg [31:0]      selected_word;
    reg [`XLEN-1:0] load_data;

    always @(*) begin
        case (offset)
            3'd0: selected_byte = dmem_rdata[7:0];
            3'd1: selected_byte = dmem_rdata[15:8];
            3'd2: selected_byte = dmem_rdata[23:16];
            3'd3: selected_byte = dmem_rdata[31:24];
            3'd4: selected_byte = dmem_rdata[39:32];
            3'd5: selected_byte = dmem_rdata[47:40];
            3'd6: selected_byte = dmem_rdata[55:48];
            default: selected_byte = dmem_rdata[63:56];
        endcase

        case (offset[2:1])
            2'd0: selected_half = dmem_rdata[15:0];
            2'd1: selected_half = dmem_rdata[31:16];
            2'd2: selected_half = dmem_rdata[47:32];
            default: selected_half = dmem_rdata[63:48];
        endcase

        selected_word = offset[2] ? dmem_rdata[63:32] : dmem_rdata[31:0];

        case (funct3)
            `FUNCT3_LB:  load_data = {{56{selected_byte[7]}}, selected_byte};
            `FUNCT3_LBU: load_data = {56'd0, selected_byte};
            `FUNCT3_LH:  load_data = {{48{selected_half[15]}}, selected_half};
            `FUNCT3_LHU: load_data = {48'd0, selected_half};
            `FUNCT3_LW:  load_data = {{32{selected_word[31]}}, selected_word};
            `FUNCT3_LWU: load_data = {32'd0, selected_word};
            default:     load_data = dmem_rdata;          // LD
        endcase
    end

    assign wb_value = mem_read ? load_data : result;

endmodule
