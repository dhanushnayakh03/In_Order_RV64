// ============================================================
// uart_tx.v — Synthesizable UART Transmitter for RV64
// ============================================================
// Parameters:
//   CLK_FREQ_HZ : System clock frequency in Hz (default 50 MHz)
//   BAUD_RATE   : UART baud rate (default 115200)
//
// State machine: IDLE → START → DATA[0..7] → STOP → IDLE
//   Produces a 10-bit serial frame: start(0) + 8 data bits (LSB first) + stop(1)
//
// MMIO Register Map (relative to base 0x10000000):
//   +0x0  TX Data   (write-only)  : write byte[7:0] to transmit; ignored if busy
//   +0x4  TX Status (read-only)   : bit[0] = tx_busy (1=transmitting)
//
// RV64 Data Alignment:
//   For 64-bit doubleword reads, tx_busy is placed at both bit 0 (word 0)
//   and bit 32 (word 1). This ensures that whether the core performs a 64-bit 'ld'
//   at +0x0 or a 32-bit 'lw' at +0x4, bit[0] of the target register correctly
//   reflects tx_busy!
//
// Physical port:
//   uart_tx_pin : serial output line (idle high)
//
`ifndef UART_TX_V
`define UART_TX_V

module uart_tx #(
    parameter CLK_FREQ_HZ = 50_000_000,
    parameter BAUD_RATE   = 115_200
)(
    input  wire        clk,
    input  wire        rst,     // Active-high reset to match RV64 core & PYNQ-Z2 BTN

    // MMIO interface
    input  wire        en,
    input  wire        we,
    input  wire [63:0] addr,
    input  wire [63:0] wdata,
    output reg  [63:0] rdata,

    // Physical UART TX pin
    output reg         uart_tx_pin
);

    // --------------------------------------------------------
    // Baud divider: number of clock cycles per bit
    // --------------------------------------------------------
    localparam integer DIVIDER = CLK_FREQ_HZ / BAUD_RATE;

    // --------------------------------------------------------
    // State encoding
    // --------------------------------------------------------
    localparam [1:0] ST_IDLE  = 2'd0;
    localparam [1:0] ST_START = 2'd1;
    localparam [1:0] ST_DATA  = 2'd2;
    localparam [1:0] ST_STOP  = 2'd3;

    // --------------------------------------------------------
    // Internal registers
    // --------------------------------------------------------
    reg [1:0]  state;
    reg [2:0]  bit_idx;          // 0..7 bit counter
    reg [7:0]  shift_reg;        // data to transmit (LSB first)
    reg [31:0] baud_cnt;         // baud divider counter
    reg        tx_busy;

    // --------------------------------------------------------
    // MMIO read with dual-word alignment for RV64
    // --------------------------------------------------------
    always @(*) begin
        rdata = 64'b0;
        if (en && !we) begin
            // Return tx_busy in both lower word (bit 0) and upper word (bit 32).
            // That way:
            //   - ld x, 0x10000000 -> bit 0 has tx_busy
            //   - lw x, 0x10000004 -> mem_stage extracts rdata[63:32], bit 0 has tx_busy!
            rdata = {31'b0, tx_busy, 31'b0, tx_busy};
        end
    end

    // --------------------------------------------------------
    // TX state machine
    // --------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            state       <= ST_IDLE;
            bit_idx     <= 3'd0;
            shift_reg   <= 8'h00;
            baud_cnt    <= 32'd0;
            tx_busy     <= 1'b0;
            uart_tx_pin <= 1'b1; // line idle high
        end else begin
            case (state)

                // ------------------------------------------------
                ST_IDLE: begin
                    uart_tx_pin <= 1'b1;  // line idle high
                    tx_busy     <= 1'b0;
                    baud_cnt    <= 32'd0;
                    // Check for new TX write: offset +0x0 (TX Data)
                    if (en && we && (addr[3:0] == 4'h0)) begin
                        shift_reg <= wdata[7:0];
                        tx_busy   <= 1'b1;
                        state     <= ST_START;
                    end
                end

                // ------------------------------------------------
                ST_START: begin
                    uart_tx_pin <= 1'b0; // start bit (low)
                    if (baud_cnt == DIVIDER - 1) begin
                        baud_cnt <= 32'd0;
                        bit_idx  <= 3'd0;
                        state    <= ST_DATA;
                    end else begin
                        baud_cnt <= baud_cnt + 32'd1;
                    end
                end

                // ------------------------------------------------
                ST_DATA: begin
                    uart_tx_pin <= shift_reg[0]; // LSB first
                    if (baud_cnt == DIVIDER - 1) begin
                        baud_cnt  <= 32'd0;
                        shift_reg <= {1'b0, shift_reg[7:1]}; // shift right
                        if (bit_idx == 3'd7) begin
                            state <= ST_STOP;
                        end else begin
                            bit_idx <= bit_idx + 3'd1;
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 32'd1;
                    end
                end

                // ------------------------------------------------
                ST_STOP: begin
                    uart_tx_pin <= 1'b1; // stop bit (high)
                    if (baud_cnt == DIVIDER - 1) begin
                        baud_cnt <= 32'd0;
                        tx_busy  <= 1'b0;
                        state    <= ST_IDLE;
                    end else begin
                        baud_cnt <= baud_cnt + 32'd1;
                    end
                end

                default: begin
                    state       <= ST_IDLE;
                    uart_tx_pin <= 1'b1;
                end

            endcase
        end
    end

endmodule

`endif