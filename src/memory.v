// ============================================================================
// File: memory.v
// Description: Dual-Port Unified Memory (Synthesizable to FPGA Block RAM)
// Port A: 32-bit Instruction Fetch
// Port B: 64-bit Byte-Maskable Data Memory (Loads and Stores)
// Standard Verilog-2001
// ============================================================================

`include "rv64_defs.v"

module memory #(
    parameter MEM_SIZE_BYTES = 65536,            // 64 KB
    parameter MEM_DEPTH      = MEM_SIZE_BYTES / 8 // 8192 doublewords (64-bit)
)(
    input  wire                  clk,
    input  wire                  rst,

    // Port A: Instruction Fetch Interface (Read-only)
    input  wire [`XLEN-1:0]      imem_addr,
    output wire [`ILEN-1:0]      imem_rdata,

    // Port B: Data Memory Interface (Read/Write)
    input  wire [`XLEN-1:0]      dmem_addr,
    input  wire [`XLEN-1:0]      dmem_wdata,
    input  wire [7:0]            dmem_byte_en,
    input  wire                  dmem_en,
    input  wire                  dmem_wen,
    output reg  [`XLEN-1:0]      dmem_rdata
);

    // 64-bit wide unified memory array
    (* ram_style = "block" *)
    reg [63:0] mem_array [0:MEM_DEPTH-1];

    // Word and doubleword address decoding
    wire [$clog2(MEM_DEPTH)-1:0] i_index = imem_addr[$clog2(MEM_DEPTH)+2:3];
    wire [$clog2(MEM_DEPTH)-1:0] d_index = dmem_addr[$clog2(MEM_DEPTH)+2:3];

    // ------------------------------------------------------------------------
    // Port A: Instruction Fetch (Combinational read for 1-cycle fetch)
    // ------------------------------------------------------------------------
    wire [63:0] i_line = mem_array[i_index];
    assign imem_rdata = imem_addr[2] ? i_line[63:32] : i_line[31:0];

    // ------------------------------------------------------------------------
    // Port B: Data Memory (Synchronous byte-masked write, Combinational/Sync read)
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        if (dmem_en && dmem_wen) begin
            if (dmem_byte_en[0]) mem_array[d_index][ 7: 0] <= dmem_wdata[ 7: 0];
            if (dmem_byte_en[1]) mem_array[d_index][15: 8] <= dmem_wdata[15: 8];
            if (dmem_byte_en[2]) mem_array[d_index][23:16] <= dmem_wdata[23:16];
            if (dmem_byte_en[3]) mem_array[d_index][31:24] <= dmem_wdata[31:24];
            if (dmem_byte_en[4]) mem_array[d_index][39:32] <= dmem_wdata[39:32];
            if (dmem_byte_en[5]) mem_array[d_index][47:40] <= dmem_wdata[47:40];
            if (dmem_byte_en[6]) mem_array[d_index][55:48] <= dmem_wdata[55:48];
            if (dmem_byte_en[7]) mem_array[d_index][63:56] <= dmem_wdata[63:56];
        end
    end

    // Combinational read for data port
    always @(*) begin
        if (dmem_en && !dmem_wen) begin
            dmem_rdata = mem_array[d_index];
        end else begin
            dmem_rdata = 64'd0;
        end
    end

endmodule
