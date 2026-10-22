// ============================================================
// uart_rx.v — Synthesizable UART Receiver for RV64
// ============================================================
// Parameters:
//   CLK_FREQ_HZ : System clock frequency in Hz (default 50 MHz)
//   BAUD_RATE   : UART baud rate (default 115200)
//
// 16x oversampled: samples the RX line at 16× baud rate.
//   SAMPLE_DIV = CLK_FREQ_HZ / (BAUD_RATE * 16)
// Start bit detected on falling edge; samples at bit centre (8th sample).
//
// 8-byte synchronous FIFO: stores received bytes.
//   Full → new bytes dropped (no overflow corruption).
//
// MMIO Register Map (relative to base 0x10000000):
//   +0x8  RX Data   (read-only) : reads oldest byte and pops FIFO
//   +0xC  RX Status (read-only) : bit[0] = rx_ready (1 = FIFO not empty)
//
// RV64 Data Alignment:
//   - Lower word (bits 31:0) at +0x8 contains RX Data in bits [7:0] and rx_ready in bit [8].
//   - Upper word (bits 63:32) at +0xC contains rx_ready in bit [32].
//   This ensures that a 32-bit 'lw' from +0xC extracts bit[0] = rx_ready,
//   and a read from +0x8 extracts the character, without status polling popping the FIFO!
//
// Physical port:
//   uart_rx_pin : serial input line (idle high)
//                 2-FF synchroniser included for metastability
//
`ifndef UART_RX_V
`define UART_RX_V

module uart_rx #(
    parameter CLK_FREQ_HZ = 50_000_000,
    parameter BAUD_RATE   = 115_200
)(
    input  wire        clk,
    input  wire        rst,     // Active-high reset to match RV64 core & PYNQ-Z2 BTN

    // MMIO interface
    input  wire        en,
    input  wire        we,
    input  wire [63:0] addr,
    output reg  [63:0] rdata,

    // Physical UART RX pin
    input  wire        uart_rx_pin
);

    // --------------------------------------------------------
    // Timing parameters: cycles per 1/16th baud period
    // --------------------------------------------------------
    localparam integer SAMPLE_DIV = CLK_FREQ_HZ / (BAUD_RATE * 16);

    // --------------------------------------------------------
    // 2-FF metastability synchroniser & edge detector
    // --------------------------------------------------------
    reg rx_sync0, rx_sync1;
    reg rx_in_prev;
    wire rx_in = rx_sync1;
    wire rx_falling = rx_in_prev && !rx_in;

    always @(posedge clk) begin
        if (rst) begin
            rx_sync0   <= 1'b1;
            rx_sync1   <= 1'b1;
            rx_in_prev <= 1'b1;
        end else begin
            rx_sync0   <= uart_rx_pin;
            rx_sync1   <= rx_sync0;
            rx_in_prev <= rx_in;
        end
    end

    // --------------------------------------------------------
    // 8-byte FIFO
    // --------------------------------------------------------
    localparam FIFO_DEPTH = 8;
    reg [7:0] fifo [0:FIFO_DEPTH-1];
    reg [3:0] fifo_wr_ptr;  // write pointer (0..7)
    reg [3:0] fifo_rd_ptr;  // read pointer  (0..7)
    reg [3:0] fifo_count;   // number of bytes in FIFO
    wire fifo_full  = (fifo_count == FIFO_DEPTH);
    wire fifo_empty = (fifo_count == 4'd0);

    // --------------------------------------------------------
    // State machine
    // --------------------------------------------------------
    localparam [2:0] ST_IDLE      = 3'd0;
    localparam [2:0] ST_START     = 3'd1;
    localparam [2:0] ST_DATA      = 3'd2;
    localparam [2:0] ST_STOP      = 3'd3;
    localparam [2:0] ST_WAIT_IDLE = 3'd4;

    reg [2:0]  state;
    reg [2:0]  bit_idx;        // 0..7 bit counter
    reg [7:0]  rx_shift;       // shift register (receives LSB first)
    reg [3:0]  oversample_cnt; // counts oversampled ticks (0..15)
    reg        sample_tick;    // 1 pulse every 1/16th baud period

    // --------------------------------------------------------
    // Robust 16-bit integer baud tick generator (No 24-bit truncation bug)
    // --------------------------------------------------------
    reg [15:0] sample_cnt;

    always @(posedge clk) begin
        if (rst) begin
            sample_cnt  <= 16'd0;
            sample_tick <= 1'b0;
        end else begin
            if (state == ST_IDLE && rx_falling) begin
                // Synchronize sample phase precisely to falling edge of start bit
                sample_cnt  <= 16'd0;
                sample_tick <= 1'b0;
            end else if (sample_cnt == SAMPLE_DIV - 1) begin
                sample_cnt  <= 16'd0;
                sample_tick <= 1'b1;
            end else begin
                sample_cnt  <= sample_cnt + 16'd1;
                sample_tick <= 1'b0;
            end
        end
    end

    // --------------------------------------------------------
    // RX state machine & FIFO management
    // --------------------------------------------------------
    wire fifo_push = (state == ST_STOP) && sample_tick && (oversample_cnt == 4'd15) && (rx_in == 1'b1) && !fifo_full;
    // Pop occurs ONLY when reading RX Data (+0x8), never when polling RX Status (+0xC)
    wire fifo_pop  = en && !we && (addr[3:0] == 4'h8) && !fifo_empty;

    always @(posedge clk) begin
        if (rst) begin
            state          <= ST_IDLE;
            bit_idx        <= 3'd0;
            rx_shift       <= 8'h00;
            oversample_cnt <= 4'd0;
            fifo_wr_ptr    <= 4'd0;
            fifo_rd_ptr    <= 4'd0;
            fifo_count     <= 4'd0;
        end else begin
            // FIFO push on valid stop bit
            if (fifo_push) begin
                fifo[fifo_wr_ptr[2:0]] <= rx_shift;
                fifo_wr_ptr            <= fifo_wr_ptr + 4'd1;
            end

            // FIFO pop on MMIO read of RX Data
            if (fifo_pop) begin
                fifo_rd_ptr <= fifo_rd_ptr + 4'd1;
            end

            // Concurrent FIFO counter update
            if (fifo_push && !fifo_pop) begin
                fifo_count <= fifo_count + 4'd1;
            end else if (!fifo_push && fifo_pop) begin
                fifo_count <= fifo_count - 4'd1;
            end

            // UART RX State Machine
            case (state)
                ST_IDLE: begin
                    if (rx_falling) begin
                        state          <= ST_START;
                        oversample_cnt <= 4'd0;
                    end
                end

                ST_START: begin
                    if (sample_tick) begin
                        if (oversample_cnt == 4'd7) begin
                            oversample_cnt <= 4'd0;
                            if (rx_in == 1'b0) begin
                                bit_idx <= 3'd0;
                                state   <= ST_DATA;
                            end else begin
                                state   <= ST_IDLE;
                            end
                        end else begin
                            oversample_cnt <= oversample_cnt + 4'd1;
                        end
                    end
                end

                ST_DATA: begin
                    if (sample_tick) begin
                        if (oversample_cnt == 4'd15) begin
                            oversample_cnt <= 4'd0;
                            rx_shift       <= {rx_in, rx_shift[7:1]}; // LSB first
                            if (bit_idx == 3'd7) begin
                                state <= ST_STOP;
                            end else begin
                                bit_idx <= bit_idx + 3'd1;
                            end
                        end else begin
                            oversample_cnt <= oversample_cnt + 4'd1;
                        end
                    end
                end

                ST_STOP: begin
                    if (sample_tick) begin
                        if (oversample_cnt == 4'd15) begin
                            oversample_cnt <= 4'd0;
                            if (rx_in == 1'b1) begin
                                state <= ST_IDLE;
                            end else begin
                                state <= ST_WAIT_IDLE; // Framing error: wait for line idle
                            end
                        end else begin
                            oversample_cnt <= oversample_cnt + 4'd1;
                        end
                    end
                end

                ST_WAIT_IDLE: begin
                    // Wait until line returns high before listening for new start bits
                    if (rx_in == 1'b1) begin
                        state <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    // --------------------------------------------------------
    // MMIO read with dual-word alignment for RV64
    // --------------------------------------------------------
    wire rx_ready = !fifo_empty;
    wire [7:0] current_byte = fifo[fifo_rd_ptr[2:0]];

    always @(*) begin
        rdata = 64'b0;
        if (en && !we) begin
            // Lower word: byte data in [7:0], rx_ready in [8]
            // Upper word: rx_ready in [32] (so lw from +0xC gets bit 0 = rx_ready)
            rdata = {31'b0, rx_ready, 23'b0, rx_ready, current_byte};
        end
    end

endmodule

`endif