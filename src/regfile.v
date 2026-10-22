// ============================================================================
// File: regfile.v
// Description: 32 x 64-bit Register File with internal WB->ID forwarding
// Standard Verilog-2001
// ============================================================================

`include "rv64_defs.v"

module regfile (
    input  wire                  clk,
    input  wire                  rst,
    
    // Read Port 1
    input  wire [4:0]            raddr1,
    output wire [`XLEN-1:0]      rdata1,
    
    // Read Port 2
    input  wire [4:0]            raddr2,
    output wire [`XLEN-1:0]      rdata2,
    
    // Write Port
    input  wire                  wen,
    input  wire [4:0]            waddr,
    input  wire [`XLEN-1:0]      wdata
);

    reg [`XLEN-1:0] regs [0:31];
    integer i;

    // Synchronous write
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1) begin
                regs[i] <= {`XLEN{1'b0}};
            end
        end else if (wen && (waddr != 5'd0)) begin
            regs[waddr] <= wdata;
        end
    end

    // Read Port 1 with internal forwarding (write-before-read)
    assign rdata1 = (raddr1 == 5'd0) ? {`XLEN{1'b0}} :
                    (wen && (waddr == raddr1)) ? wdata : regs[raddr1];

    // Read Port 2 with internal forwarding (write-before-read)
    assign rdata2 = (raddr2 == 5'd0) ? {`XLEN{1'b0}} :
                    (wen && (waddr == raddr2)) ? wdata : regs[raddr2];

endmodule
