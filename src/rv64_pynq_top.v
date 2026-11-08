// ============================================================================
// File: rv64_pynq_top.v
// Description: AXI4-Lite wrapper for the 7-stage in-order RV64 core on PYNQ-Z2.
//              Add this module to a Vivado block design (Add Module), connect
//              s_axi to the Zynq PS M_AXI_GP0 through an AXI interconnect /
//              SmartConnect, and drive s_axi_aclk / s_axi_aresetn from FCLK0 and
//              the PS reset block. The core runs on s_axi_aclk.
//
// Register / Memory Map (byte offsets, 32-bit accesses):
//   0x00000 - 0x0FFFF  Memory (64 KB). Writes go to BOTH the instruction and
//                      the data BRAM (program image); reads return the data
//                      BRAM. Write only while the core is held in reset.
//   0x10000  CTRL      [0] core reset: 1 = hold in reset (default), 0 = run   R/W
//   0x10004  STATUS    [0] halted (WFI or illegal reached WB)                 R
//                      [1] error  (halted on illegal / unsupported instr)
//   0x10008  CYCLES    cycle count                                            R
//   0x1000C  RETIRED   retired instruction count                              R
//   0x10010  ERRPC_LO  PC of illegal instruction [31:0]                       R
//   0x10014  ERRPC_HI  PC of illegal instruction [63:32]                      R
//   0x10100 + 8*i      x[i][31:0]   (i = 0..31)                               R
//   0x10104 + 8*i      x[i][63:32]
//
// Note: asserting CTRL reset clears the register file and counters, so read
// results before resetting the core again.
// Standard Verilog-2001
// ============================================================================

`include "rv64_defs.v"

module rv64_pynq_top #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 18,     // 256 KB window
    parameter integer MEM_SIZE_BYTES     = 65536   // IMEM and DMEM size each
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
    input  wire                              s_axi_rready
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

    // Control register
    reg reg_reset_core;   // 0x10000: 1 = Hold CPU in reset, 0 = Run

    // Core status
    wire             core_halted;
    wire             core_error;
    wire [`XLEN-1:0] core_error_pc;
    wire [31:0]      core_cycle_cnt;
    wire [31:0]      core_retired_cnt;
    wire [`XLEN-1:0] core_dbg_reg_data;

    wire axi_write_en = axi_wready && s_axi_wvalid && axi_awready && s_axi_awvalid;

    // AXI Write Address & Data Handling
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            axi_awready    <= 1'b0;
            axi_wready     <= 1'b0;
            axi_bvalid     <= 1'b0;
            axi_bresp      <= 2'b0;
            axi_awaddr     <= {C_S_AXI_ADDR_WIDTH{1'b0}};
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
                case (axi_awaddr[8:0])
                    9'h000: reg_reset_core <= s_axi_wdata[0];
                    default: ;
                endcase
            end
        end
    end

    // ========================================================================
    // 2. AXI Read Handling
    //    The data BRAM has a 1-cycle synchronous read, so a read takes:
    //    RD_ADDR (address accepted) -> RD_MEM (BRAM port B sampled, retried if
    //    a host write occupies the port) -> RD_DATA (rvalid) -> idle.
    // ========================================================================
    localparam RD_IDLE = 2'd0, RD_MEM = 2'd1, RD_WAIT = 2'd2, RD_DATA = 2'd3;
    reg  [1:0]  rd_state;
    wire [31:0] host_mem_rdata;
    wire        host_wr_mem = axi_write_en && !axi_awaddr[16];   // memory write this cycle

    // Architectural register readback: 0x10100 + 8*i (+4 for upper half)
    wire [4:0]  dbg_reg_idx  = axi_araddr[7:3];
    wire [31:0] dbg_reg_word = axi_araddr[2] ? core_dbg_reg_data[63:32]
                                             : core_dbg_reg_data[31:0];

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            rd_state    <= RD_IDLE;
            axi_arready <= 1'b0;
            axi_rvalid  <= 1'b0;
            axi_rresp   <= 2'b0;
            axi_araddr  <= {C_S_AXI_ADDR_WIDTH{1'b0}};
            axi_rdata   <= {C_S_AXI_DATA_WIDTH{1'b0}};
        end else begin
            axi_arready <= 1'b0;
            case (rd_state)
                RD_IDLE: begin
                    if (s_axi_arvalid && !axi_arready) begin
                        axi_arready <= 1'b1;           // accept address (1-cycle pulse)
                        axi_araddr  <= s_axi_araddr;
                        rd_state    <= RD_MEM;
                    end
                end
                RD_MEM: begin
                    // BRAM port B samples axi_araddr at the end of this cycle,
                    // unless a host write owns the port this cycle.
                    if (!host_wr_mem) rd_state <= RD_WAIT;
                end
                RD_WAIT: begin
                    axi_rvalid <= 1'b1;
                    axi_rresp  <= 2'b00; // OKAY
                    if (axi_araddr[16]) begin
                        if (axi_araddr[8]) begin
                            axi_rdata <= dbg_reg_word;  // x0..x31
                        end else begin
                            case (axi_araddr[7:0])
                                8'h00: axi_rdata <= {31'b0, reg_reset_core};
                                8'h04: axi_rdata <= {30'b0, core_error, core_halted};
                                8'h08: axi_rdata <= core_cycle_cnt;
                                8'h0C: axi_rdata <= core_retired_cnt;
                                8'h10: axi_rdata <= core_error_pc[31:0];
                                8'h14: axi_rdata <= core_error_pc[63:32];
                                default: axi_rdata <= 32'd0;
                            endcase
                        end
                    end else begin
                        axi_rdata <= host_mem_rdata;
                    end
                    rd_state <= RD_DATA;
                end
                RD_DATA: begin
                    if (s_axi_rready) begin
                        axi_rvalid <= 1'b0;
                        rd_state   <= RD_IDLE;
                    end
                end
            endcase
        end
    end

    // ========================================================================
    // 3. Instruction and Data Block RAMs
    //    Port A: core. Port B: host (writes go to both, reads from DMEM).
    // ========================================================================
    wire [`XLEN-1:0] core_imem_addr;
    wire             core_imem_en;
    wire [`ILEN-1:0] core_imem_rdata;
    wire [`XLEN-1:0] core_dmem_addr;
    wire [`XLEN-1:0] core_dmem_wdata;
    wire [7:0]       core_dmem_we;
    wire             core_dmem_en;
    wire [`XLEN-1:0] core_dmem_rdata;

    wire rst_core_internal = (!s_axi_aresetn) || reg_reset_core;

    wire [31:0] host_waddr = {{(32-C_S_AXI_ADDR_WIDTH){1'b0}}, axi_awaddr};
    wire [31:0] host_raddr = {{(32-C_S_AXI_ADDR_WIDTH){1'b0}}, axi_araddr};
    wire        host_rd_mem = (rd_state == RD_MEM) && !axi_araddr[16];

    imem #(
        .MEM_SIZE_BYTES (MEM_SIZE_BYTES)
    ) imem_inst (
        .clk        (s_axi_aclk),
        .en         (core_imem_en),
        .addr       (core_imem_addr),
        .rdata      (core_imem_rdata),
        .host_we    (host_wr_mem),
        .host_addr  (host_waddr),
        .host_wstrb (s_axi_wstrb),
        .host_wdata (s_axi_wdata)
    );

    dmem #(
        .MEM_SIZE_BYTES (MEM_SIZE_BYTES)
    ) dmem_inst (
        .clk        (s_axi_aclk),
        .en         (core_dmem_en && !rst_core_internal),
        .we         (core_dmem_we),
        .addr       (core_dmem_addr),
        .wdata      (core_dmem_wdata),
        .rdata      (core_dmem_rdata),
        .host_en    (host_wr_mem || host_rd_mem),
        .host_wstrb (host_wr_mem ? s_axi_wstrb : 4'b0000),
        .host_addr  (host_wr_mem ? host_waddr : host_raddr),
        .host_wdata (s_axi_wdata),
        .host_rdata (host_mem_rdata)
    );

    // ========================================================================
    // 4. RV64 Core Instance
    // ========================================================================
    core_top core_inst (
        .clk                (s_axi_aclk),
        .rst                (rst_core_internal),
        .imem_addr          (core_imem_addr),
        .imem_en            (core_imem_en),
        .imem_rdata         (core_imem_rdata),
        .dmem_addr          (core_dmem_addr),
        .dmem_wdata         (core_dmem_wdata),
        .dmem_we            (core_dmem_we),
        .dmem_en            (core_dmem_en),
        .dmem_rdata         (core_dmem_rdata),
        .halted             (core_halted),
        .error              (core_error),
        .error_pc           (core_error_pc),
        .cycle_count        (core_cycle_cnt),
        .retired_inst_count (core_retired_cnt),
        .dbg_reg_addr       (dbg_reg_idx),
        .dbg_reg_data       (core_dbg_reg_data)
    );

endmodule
