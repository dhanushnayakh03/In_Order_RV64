// ============================================================================
// File: rv64_pynq_top.v
// Description: AXI4-Lite Unified Wrapper for 5-Stage RV64 Core on PYNQ-Z2
// Allows Jupyter Notebook (Python) on ARM PS to:
//   1. Load program binaries directly into 64 KB RAM (0x00000 - 0x0FFFF)
//   2. Read memory results after execution (e.g. at 0x1000)
//   3. Control Reset (0x10000)
//   4. Poll Halt Status (0x10004)
//   5. Read Performance Counters: Cycles (0x10008), Retired Instructions (0x1000C)
// ============================================================================

`include "rv64_defs.v"

module rv64_pynq_top #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 18   // Covers up to 256 KB address space
)(
    // AXI4-Lite Slave Interface (Connected to Zynq Processing System)
    input  wire                              s_axi_aclk,
    input  wire                              s_axi_aresetn,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_awaddr,
    input  wire [2:0]                        s_axi_awprot,
    input  wire                              s_axi_awvalid,
    output wire                              s_axi_awready,
    input  wire [C_S_AXI_DATA_WIDTH-1:0]     s_axi_wdata,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  wire                              s_axi_wvalid,
    output wire                              s_axi_wready,
    output wire [1:0]                        s_axi_bresp,
    output wire                              s_axi_bvalid,
    input  wire                              s_axi_bready,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_araddr,
    input  wire [2:0]                        s_axi_arprot,
    input  wire                              s_axi_arvalid,
    output wire                              s_axi_arready,
    output wire [C_S_AXI_DATA_WIDTH-1:0]     s_axi_rdata,
    output wire [1:0]                        s_axi_rresp,
    output wire                              s_axi_rvalid,
    input  wire                              s_axi_rready,

    // Optional Board LED Outputs for visual status
    output wire [3:0]                        leds
);

    // ========================================================================
    // 1. AXI4-Lite Handshake Logic
    // ========================================================================
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr;
    reg                          axi_awready;
    reg                          axi_wready;
    reg [1:0]                    axi_bresp;
    reg                          axi_bvalid;
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_araddr;
    reg                          axi_arready;
    reg [C_S_AXI_DATA_WIDTH-1:0] axi_rdata;
    reg [1:0]                    axi_rresp;
    reg                          axi_rvalid;

    assign s_axi_awready = axi_awready;
    assign s_axi_wready  = axi_wready;
    assign s_axi_bresp   = axi_bresp;
    assign s_axi_bvalid  = axi_bvalid;
    assign s_axi_arready = axi_arready;
    assign s_axi_rdata   = axi_rdata;
    assign s_axi_rresp   = axi_rresp;
    assign s_axi_rvalid  = axi_rvalid;

    // Control & Status Registers
    reg        reg_reset_core;    // 0x10000: 1 = Hold CPU in reset, 0 = Run
    wire       core_halted;       // 0x10004: CPU halted on WFI
    wire [31:0] core_cycle_cnt;   // 0x10008: Total CPU cycles
    wire [31:0] core_retired_cnt; // 0x1000C: Total retired instructions

    wire axi_write_en = axi_wready && s_axi_wvalid && axi_awready && s_axi_awvalid;

    // AXI Write Address & Data Handling
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            axi_awready    <= 1'b0;
            axi_wready     <= 1'b0;
            axi_bvalid     <= 1'b0;
            axi_bresp      <= 2'b0;
            reg_reset_core <= 1'b1; // Default to reset on power-up
        end else begin
            // Address Write Ready
            if (~axi_awready && s_axi_awvalid && s_axi_wvalid) begin
                axi_awready <= 1'b1;
                axi_awaddr  <= s_axi_awaddr;
            end else begin
                axi_awready <= 1'b0;
            end

            // Data Write Ready
            if (~axi_wready && s_axi_wvalid && s_axi_awvalid) begin
                axi_wready <= 1'b1;
            end else begin
                axi_wready <= 1'b0;
            end

            // Write Response
            if (axi_awready && s_axi_awvalid && axi_wready && s_axi_wvalid && ~axi_bvalid) begin
                axi_bvalid <= 1'b1;
                axi_bresp  <= 2'b00; // OKAY
            end else if (s_axi_bready && axi_bvalid) begin
                axi_bvalid <= 1'b0;
            end

            // Register Writes (Offset 0x10000 onwards)
            if (axi_write_en && axi_awaddr[16]) begin
                case (axi_awaddr[7:0])
                    8'h00: reg_reset_core <= s_axi_wdata[0];
                    default: ;
                endcase
            end
        end
    end

    // ========================================================================
    // 2. Shared 64 KB Unified RAM (Dual-Port)
    //    Port A: AXI4-Lite (Python Read/Write, 32-bit words)
    //    Port B: RV64 Core (Fetch 32-bit inst, Load/Store 64-bit doublewords)
    // ========================================================================
    localparam MEM_DEPTH = 8192; // 8192 * 64 bits = 64 KB
    reg [63:0] ram [0:MEM_DEPTH-1];

    // --- Port A: AXI Bus Access (32-bit) ---
    wire        axi_mem_we  = axi_write_en && (!axi_awaddr[16]);
    wire [12:0] axi_mem_idx = axi_awaddr[15:3];
    wire [12:0] axi_rd_idx  = axi_araddr[15:3];
    wire [63:0] axi_line    = ram[axi_rd_idx];
    wire [31:0] axi_mem_rdata_word = axi_araddr[2] ? axi_line[63:32] : axi_line[31:0];

    // AXI Read Handling
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            axi_arready <= 1'b0;
            axi_rvalid  <= 1'b0;
            axi_rresp   <= 2'b0;
            axi_araddr  <= 0;
            axi_rdata   <= 0;
        end else begin
            // Read Address Ready
            if (~axi_arready && s_axi_arvalid) begin
                axi_arready <= 1'b1;
                axi_araddr  <= s_axi_araddr;
            end else begin
                axi_arready <= 1'b0;
            end

            // Read Data Valid & Mux
            if (axi_arready && s_axi_arvalid && ~axi_rvalid) begin
                axi_rvalid <= 1'b1;
                axi_rresp  <= 2'b00; // OKAY

                if (axi_araddr[16]) begin
                    // Register Reads
                    case (axi_araddr[7:0])
                        8'h00: axi_rdata <= {31'b0, reg_reset_core};
                        8'h04: axi_rdata <= {31'b0, core_halted};
                        8'h08: axi_rdata <= core_cycle_cnt;
                        8'h0C: axi_rdata <= core_retired_cnt;
                        default: axi_rdata <= 32'd0;
                    endcase
                end else begin
                    // Memory Read from AXI Port
                    axi_rdata <= axi_mem_rdata_word;
                end
            end else if (axi_rvalid && s_axi_rready) begin
                axi_rvalid <= 1'b0;
            end
        end
    end

    // --- Port B: RV64 Core Access ---
    wire [`XLEN-1:0] core_imem_addr;
    wire [`ILEN-1:0] core_imem_rdata;
    wire [`XLEN-1:0] core_dmem_addr;
    wire [`XLEN-1:0] core_dmem_wdata;
    wire [7:0]       core_dmem_byte_en;
    wire             core_dmem_en;
    wire             core_dmem_wen;
    reg  [`XLEN-1:0] core_dmem_rdata;

    // Core Instruction Fetch (Combinational read)
    wire [12:0] core_i_idx  = core_imem_addr[15:3];
    wire [63:0] core_i_line = ram[core_i_idx];
    assign core_imem_rdata  = core_imem_addr[2] ? core_i_line[63:32] : core_i_line[31:0];

    // Core Data Memory Index
    wire [12:0] core_d_idx  = core_dmem_addr[15:3];

    // Unified Synchronous RAM Write Process (Synthesizable across all Xilinx tools)
    always @(posedge s_axi_aclk) begin
        if (axi_mem_we) begin
            // AXI write (Python loading program or data)
            if (axi_awaddr[2]) begin
                if (s_axi_wstrb[0]) ram[axi_mem_idx][39:32] <= s_axi_wdata[7:0];
                if (s_axi_wstrb[1]) ram[axi_mem_idx][47:40] <= s_axi_wdata[15:8];
                if (s_axi_wstrb[2]) ram[axi_mem_idx][55:48] <= s_axi_wdata[23:16];
                if (s_axi_wstrb[3]) ram[axi_mem_idx][63:56] <= s_axi_wdata[31:24];
            end else begin
                if (s_axi_wstrb[0]) ram[axi_mem_idx][7:0]   <= s_axi_wdata[7:0];
                if (s_axi_wstrb[1]) ram[axi_mem_idx][15:8]  <= s_axi_wdata[15:8];
                if (s_axi_wstrb[2]) ram[axi_mem_idx][23:16] <= s_axi_wdata[23:16];
                if (s_axi_wstrb[3]) ram[axi_mem_idx][31:24] <= s_axi_wdata[31:24];
            end
        end else if (core_dmem_en && core_dmem_wen && !reg_reset_core) begin
            // Core store instruction (RV64 write)
            if (core_dmem_byte_en[0]) ram[core_d_idx][7:0]   <= core_dmem_wdata[7:0];
            if (core_dmem_byte_en[1]) ram[core_d_idx][15:8]  <= core_dmem_wdata[15:8];
            if (core_dmem_byte_en[2]) ram[core_d_idx][23:16] <= core_dmem_wdata[23:16];
            if (core_dmem_byte_en[3]) ram[core_d_idx][31:24] <= core_dmem_wdata[31:24];
            if (core_dmem_byte_en[4]) ram[core_d_idx][39:32] <= core_dmem_wdata[39:32];
            if (core_dmem_byte_en[5]) ram[core_d_idx][47:40] <= core_dmem_wdata[47:40];
            if (core_dmem_byte_en[6]) ram[core_d_idx][55:48] <= core_dmem_wdata[55:48];
            if (core_dmem_byte_en[7]) ram[core_d_idx][63:56] <= core_dmem_wdata[63:56];
        end
    end

    always @(*) begin
        if (core_dmem_en && !core_dmem_wen) begin
            core_dmem_rdata = ram[core_d_idx];
        end else begin
            core_dmem_rdata = 64'd0;
        end
    end

    // ========================================================================
    // 3. RV64 Core Instance
    // ========================================================================
    wire rst_core_internal = (!s_axi_aresetn) || reg_reset_core;

    core_top core_inst (
        .clk                (s_axi_aclk),
        .rst                (rst_core_internal),
        .imem_addr          (core_imem_addr),
        .imem_rdata         (core_imem_rdata),
        .dmem_addr          (core_dmem_addr),
        .dmem_wdata         (core_dmem_wdata),
        .dmem_byte_en       (core_dmem_byte_en),
        .dmem_en            (core_dmem_en),
        .dmem_wen           (core_dmem_wen),
        .dmem_rdata         (core_dmem_rdata),
        .halted             (core_halted),
        .cycle_count        (core_cycle_cnt),
        .retired_inst_count (core_retired_cnt)
    );

    // ========================================================================
    // 4. Status LEDs
    // ========================================================================
    // LD0: Reset active (ON when core held in reset by Python)
    // LD1: Halted on WFI (ON when execution completes)
    // LD2: Memory write activity
    // LD3: AXI communication activity
    assign leds[0] = reg_reset_core;
    assign leds[1] = core_halted;
    assign leds[2] = core_dmem_en && core_dmem_wen;
    assign leds[3] = axi_write_en || s_axi_arvalid;

endmodule
