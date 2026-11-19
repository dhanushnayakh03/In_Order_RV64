// ============================================================================
// File: imem.v
// Description: Instruction memory, inferred as Xilinx Block RAM
//              (simple dual port, synchronous read).
//   Port A: core instruction fetch, 64-bit synchronous read, 32-bit output.
//           The address is sampled at the clock edge ending IF1; the
//           instruction is valid during IF2. en=0 holds the output (stall).
//   Port B: host (AXI) write-only port used to load the program image.
//
// BRAM inference rules followed (do not break when editing):
//   - registered read only, no reset / init loop on the array
//   - at most two ports, byte-write coded with per-byte enables
//   - both ports 64 bits wide; the 32-bit select happens after the BRAM
// Standard Verilog-2001
// ============================================================================

`include "rv64_defs.v"

module imem #(
    parameter MEM_SIZE_BYTES = 65536,              // 64 KB
    parameter MEM_DEPTH      = MEM_SIZE_BYTES / 8, // 8192 x 64-bit
    parameter IDX_W          = $clog2(MEM_DEPTH)
)(
    input  wire                  clk,

    // Port A: instruction fetch (read-only)
    input  wire                  en,
    input  wire [`XLEN-1:0]      addr,
    output wire [`ILEN-1:0]      rdata,

    // Port B: host write port (32-bit word, byte strobes)
    input  wire                  host_we,
    input  wire [31:0]           host_addr,
    input  wire [3:0]            host_wstrb,
    input  wire [31:0]           host_wdata
);

    (* ram_style = "block" *)
    reg [63:0] mem_array [0:MEM_DEPTH-1];

    // ------------------------------------------------------------------------
    // Port A: synchronous 64-bit read, word select after the BRAM
    // ------------------------------------------------------------------------
    reg [63:0] dout_a;
    reg        sel_hi;

    always @(posedge clk) begin
        if (en) begin
            dout_a <= mem_array[addr[IDX_W+2:3]];
            sel_hi <= addr[2];
        end
    end

    assign rdata = sel_hi ? dout_a[63:32] : dout_a[31:0];

    // ------------------------------------------------------------------------
    // Port B: host byte-masked write
    // ------------------------------------------------------------------------
    wire [IDX_W-1:0] b_idx = host_addr[IDX_W+2:3];
    wire [7:0]       b_be  = host_addr[2] ? {host_wstrb, 4'b0000} : {4'b0000, host_wstrb};
    wire [63:0]      b_din = {host_wdata, host_wdata};

    integer i;
    always @(posedge clk) begin
        if (host_we) begin
            for (i = 0; i < 8; i = i + 1) begin
                if (b_be[i]) mem_array[b_idx][8*i +: 8] <= b_din[8*i +: 8];
            end
        end
    end

endmodule
