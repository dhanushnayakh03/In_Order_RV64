// ============================================================================
// File: mem_stage.v
// Description: Memory (MEM) stage for RV64 load/store alignment & sign-extension
// Standard Verilog-2001
// ============================================================================

`include "rv64_defs.v"

module mem_stage (
    // Inputs from EX/MEM pipeline register
    input  wire [`XLEN-1:0]      alu_result,
    input  wire [`XLEN-1:0]      store_data,
    input  wire [2:0]            funct3,
    input  wire                  mem_read,
    input  wire                  mem_write,

    // Data memory interface
    output wire [`XLEN-1:0]      dmem_addr,
    output reg  [`XLEN-1:0]      dmem_wdata,
    output reg  [7:0]            dmem_byte_en,
    output wire                  dmem_en,
    output wire                  dmem_wen,
    input  wire [`XLEN-1:0]      dmem_rdata,

    // Formatted load data to MEM/WB register
    output reg  [`XLEN-1:0]      load_data
);

    wire [2:0] offset = alu_result[2:0];

    // Memory address (full address passed to interconnect / MMIO)
    assign dmem_addr = alu_result;
    assign dmem_en   = mem_read | mem_write;
    assign dmem_wen  = mem_write;

    // Store formatting: byte enable generation and data alignment
    always @(*) begin
        dmem_byte_en = 8'b00000000;
        dmem_wdata   = {`XLEN{1'b0}};

        if (mem_write) begin
            case (funct3)
                `FUNCT3_SB: begin
                    dmem_byte_en = 8'b00000001 << offset;
                    dmem_wdata   = store_data[7:0] << (offset * 8);
                end
                `FUNCT3_SH: begin
                    dmem_byte_en = 8'b00000011 << (offset & 3'b110);
                    dmem_wdata   = store_data[15:0] << ((offset & 3'b110) * 8);
                end
                `FUNCT3_SW: begin
                    dmem_byte_en = offset[2] ? 8'b11110000 : 8'b00001111;
                    dmem_wdata   = offset[2] ? {store_data[31:0], 32'd0} : {32'd0, store_data[31:0]};
                end
                `FUNCT3_SD: begin
                    dmem_byte_en = 8'b11111111;
                    dmem_wdata   = store_data;
                end
                default: begin
                    dmem_byte_en = 8'b00000000;
                    dmem_wdata   = {`XLEN{1'b0}};
                end
            endcase
        end
    end

    // Load formatting: extraction and sign/zero extension
    reg [7:0]  selected_byte;
    reg [15:0] selected_half;
    reg [31:0] selected_word;

    always @(*) begin
        // Byte slice
        case (offset)
            3'd0: selected_byte = dmem_rdata[7:0];
            3'd1: selected_byte = dmem_rdata[15:8];
            3'd2: selected_byte = dmem_rdata[23:16];
            3'd3: selected_byte = dmem_rdata[31:24];
            3'd4: selected_byte = dmem_rdata[39:32];
            3'd5: selected_byte = dmem_rdata[47:40];
            3'd6: selected_byte = dmem_rdata[55:48];
            3'd7: selected_byte = dmem_rdata[63:56];
        endcase

        // Halfword slice (aligned to 2 bytes)
        case (offset[2:1])
            2'd0: selected_half = dmem_rdata[15:0];
            2'd1: selected_half = dmem_rdata[31:16];
            2'd2: selected_half = dmem_rdata[47:32];
            2'd3: selected_half = dmem_rdata[63:48];
        endcase

        // Word slice (aligned to 4 bytes)
        selected_word = offset[2] ? dmem_rdata[63:32] : dmem_rdata[31:0];

        // Format final load data based on funct3
        case (funct3)
            `FUNCT3_LB:  load_data = {{56{selected_byte[7]}}, selected_byte};
            `FUNCT3_LBU: load_data = {56'd0, selected_byte};
            `FUNCT3_LH:  load_data = {{48{selected_half[15]}}, selected_half};
            `FUNCT3_LHU: load_data = {48'd0, selected_half};
            `FUNCT3_LW:  load_data = {{32{selected_word[31]}}, selected_word};
            `FUNCT3_LWU: load_data = {32'd0, selected_word};
            `FUNCT3_LD:  load_data = dmem_rdata;
            default:     load_data = dmem_rdata;
        endcase
    end

endmodule
