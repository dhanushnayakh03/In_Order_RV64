// ============================================================================
// File: fpga_top.v ( unrealated currently !)
// Description: Top-Level FPGA Wrapper for RV64 Core on PYNQ-Z2 Board
// Interfaces:
//   - Clock: 125 MHz Oscillator (H16) -> 50 MHz via Xilinx MMCM/PLL
//   - Reset: BTN0 (D19, Active-High)
//   - UART TX: Arduino Pin D1 (W14) @ 115200 Baud
//   - UART RX: Arduino Pin D0 (Y14) @ 115200 Baud
//   - LEDs: LD0 (Heartbeat), LD1 (Halted Status), LD2/LD3 (Activity)
// ============================================================================

`include "rv64_defs.v"

module fpga_top (
    input  wire        sys_clk,       // 125 MHz PYNQ-Z2 oscillator (Pin H16)
    input  wire        sys_rst,       // BTN0 push button (Pin D19, Active-High)

    // Physical UART Pins (Arduino Header D0/D1)
    input  wire        uart_rx_pin,   // Pin Y14 (RX)
    output wire        uart_tx_pin,   // Pin W14 (TX)

    // Physical Status LEDs
    output wire [3:0]  leds           // LD0-LD3 (R14, P14, N16, M16)
);

    // ========================================================================
    // 1. Clock Generation: 125 MHz -> 50 MHz using Xilinx PLLE2_BASE
    // ========================================================================
    wire clk_50m;
    wire clk_fb;
    wire pll_locked;

`ifdef SYNTHESIS
    PLLE2_BASE #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKFBOUT_MULT      (8),            // VCO = 125 MHz * 8 = 1000 MHz (VCO range: 800-1600 MHz)
        .CLKFBOUT_PHASE     (0.0),
        .CLKIN1_PERIOD      (8.0),          // Input clock period: 8 ns (125 MHz)
        .CLKOUT0_DIVIDE     (20),           // 1000 MHz / 20 = 50 MHz
        .CLKOUT0_DUTY_CYCLE (0.5),
        .CLKOUT0_PHASE      (0.0),
        .DIVCLK_DIVIDE      (1),
        .REF_JITTER1        (0.01),
        .STARTUP_WAIT       ("FALSE")
    ) pll_inst (
        .CLKOUT0            (clk_50m),
        .CLKOUT1            (),
        .CLKOUT2            (),
        .CLKOUT3            (),
        .CLKOUT4            (),
        .CLKOUT5            (),
        .CLKFBOUT           (clk_fb),
        .CLKIN1             (sys_clk),
        .PWRDWN             (1'b0),
        .RST                (1'b0),
        .CLKFBIN            (clk_fb),
        .LOCKED             (pll_locked)
    );
`else
    // Behavioral clock model for non-Vivado simulation (iverilog)
    reg clk_50m_reg = 0;
    reg [2:0] sim_div = 0;
    always @(posedge sys_clk) begin
        if (sim_div == 2) begin
            sim_div <= 0;
            clk_50m_reg <= ~clk_50m_reg;
        end else begin
            sim_div <= sim_div + 1;
        end
    end
    assign clk_50m = clk_50m_reg;
    assign pll_locked = 1'b1;
`endif

    // Synchronize reset to 50 MHz clock domain
    reg rst_sync1, rst_sync2;
    wire core_rst = rst_sync2 || !pll_locked;

    always @(posedge clk_50m or posedge sys_rst) begin
        if (sys_rst) begin
            rst_sync1 <= 1'b1;
            rst_sync2 <= 1'b1;
        end else begin
            rst_sync1 <= 1'b0;
            rst_sync2 <= rst_sync1;
        end
    end

    // ========================================================================
    // 2. Interconnect & Address Decoding
    // ========================================================================
    // Memory Map:
    //   0x00000000 - 0x0000FFFF : 64 KB Unified RAM (memory.v)
    //   0x10000000 - 0x1000000F : UART MMIO Controller (uart_tx.v, uart_rx.v)

    wire [`XLEN-1:0] imem_addr;
    wire [`ILEN-1:0] imem_rdata;

    wire [`XLEN-1:0] dmem_addr;
    wire [`XLEN-1:0] dmem_wdata;
    wire [7:0]       dmem_byte_en;
    wire             dmem_en;
    wire             dmem_wen;
    wire [`XLEN-1:0] dmem_rdata;

    wire             halted;
    wire [31:0]      cycle_count;
    wire [31:0]      retired_inst_count;

    // Address decode
    wire is_uart = (dmem_addr >= 64'h1000_0000 && dmem_addr <= 64'h1000_000F);
    wire is_bram = !is_uart;

    wire bram_en = dmem_en && is_bram;
    wire uart_en = dmem_en && is_uart;

    wire [`XLEN-1:0] bram_rdata;
    wire [`XLEN-1:0] uart_tx_rdata;
    wire [`XLEN-1:0] uart_rx_rdata;

    // UART sub-address decode:
    //   0x10000000 (+0x0 TX Data, +0x4 TX Status) -> uart_tx
    //   0x10000008 (+0x8 RX Data, +0xC RX Status) -> uart_rx
    wire uart_is_rx = dmem_addr[3];
    wire [`XLEN-1:0] uart_rdata = uart_is_rx ? uart_rx_rdata : uart_tx_rdata;

    assign dmem_rdata = is_uart ? uart_rdata : bram_rdata;

    // ========================================================================
    // 3. Core Top Instance
    // ========================================================================
    core_top core_inst (
        .clk                (clk_50m),
        .rst                (core_rst),
        .imem_addr          (imem_addr),
        .imem_rdata         (imem_rdata),
        .dmem_addr          (dmem_addr),
        .dmem_wdata         (dmem_wdata),
        .dmem_byte_en       (dmem_byte_en),
        .dmem_en            (dmem_en),
        .dmem_wen           (dmem_wen),
        .dmem_rdata         (dmem_rdata),
        .halted             (halted),
        .cycle_count        (cycle_count),
        .retired_inst_count (retired_inst_count)
    );

    // ========================================================================
    // 4. Unified Memory Instance (Synthesizes to BRAM/Distributed RAM)
    // ========================================================================
    memory #(
        .MEM_SIZE_BYTES (65536)
    ) mem_inst (
        .clk          (clk_50m),
        .rst          (core_rst),
        .imem_addr    (imem_addr),
        .imem_rdata   (imem_rdata),
        .dmem_addr    (dmem_addr),
        .dmem_wdata   (dmem_wdata),
        .dmem_byte_en (dmem_byte_en),
        .dmem_en      (bram_en),
        .dmem_wen     (dmem_wen),
        .dmem_rdata   (bram_rdata)
    );

    // ========================================================================
    // 5. UART Transmitter Instance
    // ========================================================================
    uart_tx #(
        .CLK_FREQ_HZ (50_000_000),
        .BAUD_RATE   (115_200)
    ) u_tx (
        .clk         (clk_50m),
        .rst         (core_rst),
        .en          (uart_en && !uart_is_rx),
        .we          (dmem_wen),
        .addr        (dmem_addr),
        .wdata       (dmem_wdata),
        .rdata       (uart_tx_rdata),
        .uart_tx_pin (uart_tx_pin)
    );

    // ========================================================================
    // 6. UART Receiver Instance
    // ========================================================================
    uart_rx #(
        .CLK_FREQ_HZ (50_000_000),
        .BAUD_RATE   (115_200)
    ) u_rx (
        .clk         (clk_50m),
        .rst         (core_rst),
        .en          (uart_en && uart_is_rx),
        .we          (dmem_wen),
        .addr        (dmem_addr),
        .rdata       (uart_rx_rdata),
        .uart_rx_pin (uart_rx_pin)
    );

    // ========================================================================
    // 7. Visual Indicators & Heartbeat
    // ========================================================================
    // 1 Hz Heartbeat generator from 50 MHz clock
    reg [25:0] heartbeat_cnt;
    always @(posedge clk_50m or posedge core_rst) begin
        if (core_rst) begin
            heartbeat_cnt <= 26'd0;
        end else if (heartbeat_cnt == 26'd49_999_999) begin
            heartbeat_cnt <= 26'd0;
        end else begin
            heartbeat_cnt <= heartbeat_cnt + 26'd1;
        end
    end

    wire heartbeat = (heartbeat_cnt < 26'd25_000_000);

    // LED Assignment:
    //   LD0: 1 Hz Heartbeat (proves clock & PLL are running)
    //   LD1: Core Halted (lights up on WFI halt)
    //   LD2: Memory/UART Bus Activity
    //   LD3: PLL Locked
    assign leds[0] = heartbeat;
    assign leds[1] = halted;
    assign leds[2] = dmem_en;
    assign leds[3] = pll_locked;

endmodule
