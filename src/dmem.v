// ============================================================================
// File: dmem.v
// Description: Data memory, inferred as Xilinx Block RAM
//              (true dual port, synchronous read, byte-wide write enables).
//   Port A: core load/store port, 64-bit. Address/data/strobes are driven
//           from the EX/MEM1 register: stores write at the end of MEM1,
//           loads return data during MEM2.
//   Port B: host (AXI) port, 32-bit word access for program load and result
//           readback. Read data is valid the cycle after host_en.
//
// Loads and stores both access port A in the same stage (MEM1), so a store
// followed by a load to the same address sees the new data without any
// bypass (the store writes one edge before the load reads).
//
// BRAM inference rules followed (do not break when editing):
//   - registered read only, no reset / init loop on the array
//   - two ports max, each in its own clocked process, byte-write coded
//   - both ports 64 bits wide; the 32-bit host select happens after the BRAM
// Standard Verilog-2001
// ============================================================================

`include "rv64_defs.v"

module dmem #(
    parameter MEM_SIZE_BYTES = 65536,              // 64 KB
    parameter MEM_DEPTH      = MEM_SIZE_BYTES / 8, // 8192 x 64-bit
    parameter IDX_W          = $clog2(MEM_DEPTH)
)(
    input  wire                  clk,

    // Port A: core data port
    input  wire                  en,
    input  wire [7:0]            we,        // byte write enables (0 = load)
    input  wire [`XLEN-1:0]      addr,
    input  wire [`XLEN-1:0]      wdata,
    output reg  [`XLEN-1:0]      rdata,

    // Port B: host port (32-bit word, byte strobes)
    input  wire                  host_en,
    input  wire [3:0]            host_wstrb, // 0 = read
    input  wire [31:0]           host_addr,
    input  wire [31:0]           host_wdata,
    output wire [31:0]           host_rdata
);

    (* ram_style = "block" *)
    reg [63:0] mem_array [0:MEM_DEPTH-1];

    integer i, j;

    // ------------------------------------------------------------------------
    // Port A: core (read-first)
    // ------------------------------------------------------------------------
    wire [IDX_W-1:0] a_idx = addr[IDX_W+2:3];

    always @(posedge clk) begin
        if (en) begin
            for (i = 0; i < 8; i = i + 1) begin
                if (we[i]) mem_array[a_idx][8*i +: 8] <= wdata[8*i +: 8];
            end
            rdata <= mem_array[a_idx];
        end
    end

    // ------------------------------------------------------------------------
    // Port B: host (read-first)
    // ------------------------------------------------------------------------
    wire [IDX_W-1:0] b_idx = host_addr[IDX_W+2:3];
    wire [7:0]       b_be  = host_addr[2] ? {host_wstrb, 4'b0000} : {4'b0000, host_wstrb};
    wire [63:0]      b_din = {host_wdata, host_wdata};
    reg  [63:0]      b_dout;
    reg              b_sel_hi;

    always @(posedge clk) begin
        if (host_en) begin
            for (j = 0; j < 8; j = j + 1) begin
                if (b_be[j]) mem_array[b_idx][8*j +: 8] <= b_din[8*j +: 8];
            end
            b_dout   <= mem_array[b_idx];
            b_sel_hi <= host_addr[2];
        end
    end

    assign host_rdata = b_sel_hi ? b_dout[63:32] : b_dout[31:0];

endmodule
