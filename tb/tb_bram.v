// ============================================================================
// tb_bram.v - waveform testbench for the BRAM memories (dmem.v, imem.v)
//   Shows: 1-cycle synchronous read latency, byte-enable writes, read-first
//   behaviour, back-to-back reads, en=0 hold, host port read/write.
//   Inputs change 1 ns after a rising edge (t = 6, 16, 26, ... ns) and are
//   sampled by the memory on the NEXT rising edge (t = 15, 25, 35, ... ns).
//   VCD: tb/waves/tb_bram.vcd   (`phase` is an ASCII label of the current step)
// ============================================================================
`timescale 1ns/1ps

module tb_bram;

    reg clk = 0;
    always #5 clk = ~clk;                 // rising edges at 5, 15, 25, ... ns

    reg [8*12-1:0] phase = "RESET";

    // ---------------- DMEM ----------------
    reg         d_en = 0;
    reg  [7:0]  d_we = 0;
    reg  [63:0] d_addr = 0;
    reg  [63:0] d_wdata = 0;
    wire [63:0] d_rdata;
    reg         h_en = 0;
    reg  [3:0]  h_wstrb = 0;
    reg  [31:0] h_addr = 0;
    reg  [31:0] h_wdata = 0;
    wire [31:0] h_rdata;

    dmem #(.MEM_SIZE_BYTES(256)) u_dmem (
        .clk(clk), .en(d_en), .we(d_we), .addr(d_addr), .wdata(d_wdata), .rdata(d_rdata),
        .host_en(h_en), .host_wstrb(h_wstrb), .host_addr(h_addr),
        .host_wdata(h_wdata), .host_rdata(h_rdata));

    // contents of the two doublewords used below
    wire [63:0] dmem_word_0x10 = u_dmem.mem_array[2];
    wire [63:0] dmem_word_0x18 = u_dmem.mem_array[3];

    // ---------------- IMEM ----------------
    reg         i_en = 0;
    reg  [63:0] i_addr = 0;
    wire [31:0] i_rdata;
    reg         ih_we = 0;
    reg  [31:0] ih_addr = 0;
    reg  [31:0] ih_wdata = 0;

    imem #(.MEM_SIZE_BYTES(256)) u_imem (
        .clk(clk), .en(i_en), .addr(i_addr), .rdata(i_rdata),
        .host_we(ih_we), .host_addr(ih_addr), .host_wstrb(4'hF), .host_wdata(ih_wdata));

    integer k;

    task cyc; begin @(posedge clk); #1; end endtask   // inputs change 1 ns after each rising edge

    initial begin
        $dumpfile("waves/tb_bram.vcd");
        $dumpvars(1, tb_bram);
        for (k = 0; k < 32; k = k + 1) begin
            u_dmem.mem_array[k] = 64'd0;
            u_imem.mem_array[k] = 64'd0;
        end
        cyc;

        // ---- DMEM host write (program load): dword 0x10 = 0x8877665544332211
        phase = "HOST_WR";
        h_en = 1; h_wstrb = 4'hF; h_addr = 32'h10; h_wdata = 32'h44332211; cyc;
        h_addr = 32'h14; h_wdata = 32'h88776655;                            cyc;
        h_en = 0; h_wstrb = 0;

        // ---- read latency: request in one cycle, data after the next edge
        phase = "RD_LATENCY";
        d_en = 1; d_we = 0; d_addr = 64'h10; cyc;
        d_en = 0;                            cyc;
        cyc;

        // ---- byte-enable stores (data replicated across lanes, as MEM1 does)
        phase = "SB_0x12";
        d_en = 1; d_we = 8'b0000_0100; d_addr = 64'h12; d_wdata = {8{8'hAA}}; cyc;
        phase = "SH_0x14";
        d_we = 8'b0011_0000; d_addr = 64'h14; d_wdata = {4{16'hBBBB}};          cyc;
        phase = "SD_0x18";
        d_we = 8'hFF; d_addr = 64'h18; d_wdata = 64'hDEADBEEF_CAFEF00D;         cyc;
        phase = "SW_0x1C";
        d_we = 8'hF0; d_addr = 64'h1C; d_wdata = {2{32'h12345678}};             cyc;

        // ---- read-first: write and read the same dword in one cycle
        phase = "READ_FIRST";
        d_we = 8'hFF; d_addr = 64'h18; d_wdata = 64'h01234567_89ABCDEF;         cyc;
        phase = "READ_AFTER";
        d_we = 0;                                                               cyc;

        // ---- back-to-back reads, one per cycle
        phase = "PIPELINED";
        d_addr = 64'h10; cyc;
        d_addr = 64'h18; cyc;
        d_addr = 64'h10; cyc;

        // ---- en = 0 holds the output even though the address changes
        phase = "HOLD_EN0";
        d_en = 0; d_addr = 64'h18; cyc;
        cyc;

        // ---- host read port (result readback)
        phase = "HOST_RD";
        h_en = 1; h_wstrb = 0; h_addr = 32'h14; cyc;
        h_addr = 32'h10;                        cyc;
        h_en = 0;                               cyc;

        // ---- IMEM: host loads 4 instructions
        phase = "I_HOST_WR";
        ih_we = 1;
        ih_addr = 32'h0; ih_wdata = 32'h00A00093; cyc;   // addi x1, x0, 10
        ih_addr = 32'h4; ih_wdata = 32'h01400113; cyc;   // addi x2, x0, 20
        ih_addr = 32'h8; ih_wdata = 32'h002081B3; cyc;   // add  x3, x1, x2
        ih_addr = 32'hC; ih_wdata = 32'h10500073; cyc;   // wfi
        ih_we = 0;

        // ---- IMEM fetch: PC 0, 4, (stall 2 cycles), 8, C
        phase = "I_FETCH";
        i_en = 1; i_addr = 64'h0; cyc;
        i_addr = 64'h4;           cyc;
        phase = "I_STALL";
        i_en = 0; i_addr = 64'h8; cyc;
        cyc;
        phase = "I_FETCH";
        i_en = 1;                 cyc;
        i_addr = 64'hC;           cyc;
        i_en = 0;                 cyc;
        phase = "DONE";
        cyc; cyc;
        $finish;
    end

endmodule
