// ============================================================================
// File: rv64_defs.v
// Description: RV64I opcodes, ALU function codes, and architectural defines
// Standard Verilog-2001
// ============================================================================

`ifndef __RV64_DEFS_V__
`define __RV64_DEFS_V__

// Data width
`define XLEN 64

// Standard RISC-V 32-bit instruction width
`define ILEN 32

// 7-bit Major Opcodes
`define OPCODE_R_OP         7'b0110011 // 64-bit Register-Register
`define OPCODE_R_OP_32      7'b0111011 // 32-bit Register-Register (W-instructions)
`define OPCODE_I_OP         7'b0010011 // 64-bit Register-Immediate
`define OPCODE_I_OP_32      7'b0011011 // 32-bit Register-Immediate (W-instructions)
`define OPCODE_LOAD         7'b0000011 // Load instructions
`define OPCODE_STORE        7'b0100011 // Store instructions
`define OPCODE_BRANCH       7'b1100011 // Conditional branches
`define OPCODE_JAL          7'b1101111 // Jump and Link
`define OPCODE_JALR         7'b1100111 // Jump and Link Register
`define OPCODE_LUI          7'b0110111 // Load Upper Immediate
`define OPCODE_AUIPC        7'b0010111 // Add Upper Immediate to PC
`define OPCODE_SYSTEM       7'b1110011 // System instructions (ECALL, EBREAK, WFI)

// 3-bit funct3 for BRANCH
`define FUNCT3_BEQ          3'b000
`define FUNCT3_BNE          3'b001
`define FUNCT3_BLT          3'b100
`define FUNCT3_BGE          3'b101
`define FUNCT3_BLTU         3'b110
`define FUNCT3_BGEU         3'b111

// 3-bit funct3 for LOAD
`define FUNCT3_LB           3'b000
`define FUNCT3_LH           3'b001
`define FUNCT3_LW           3'b010
`define FUNCT3_LD           3'b011
`define FUNCT3_LBU          3'b100
`define FUNCT3_LHU          3'b101
`define FUNCT3_LWU          3'b110

// 3-bit funct3 for STORE
`define FUNCT3_SB           3'b000
`define FUNCT3_SH           3'b001
`define FUNCT3_SW           3'b010
`define FUNCT3_SD           3'b011

// ALU Operation Codes (Internal 5-bit control signal)
`define ALU_ADD             5'd0
`define ALU_SUB             5'd1
`define ALU_SLL             5'd2
`define ALU_SLT             5'd3
`define ALU_SLTU            5'd4
`define ALU_XOR             5'd5
`define ALU_SRL             5'd6
`define ALU_SRA             5'd7
`define ALU_OR              5'd8
`define ALU_AND             5'd9
// 32-bit W-instruction ALU operations (result truncated & sign-extended to 64 bits)
`define ALU_ADDW            5'd10
`define ALU_SUBW            5'd11
`define ALU_SLLW            5'd12
`define ALU_SRLW            5'd13
`define ALU_SRAW            5'd14
// Pass operand B directly (e.g. for LUI)
`define ALU_PASS_B          5'd15

// ALU Input Mux Selects
`define ALUA_SEL_RS1        1'b0
`define ALUA_SEL_PC         1'b1

`define ALUB_SEL_RS2        1'b0
`define ALUB_SEL_IMM        1'b1

// Writeback Source Selects
`define WB_SEL_ALU          2'b00
`define WB_SEL_MEM          2'b01
`define WB_SEL_PC4          2'b10

// Forwarding Multiplexer Selects
`define FWD_NONE            2'b00
`define FWD_FROM_MEM        2'b01 // From MEM/WB register
`define FWD_FROM_EX         2'b10 // From EX/MEM register

// NOP instruction: ADDI x0, x0, 0
`define NOP_INST            32'h00000013

// WFI instruction: 0x10500073
`define WFI_INST            32'h10500073

`endif // __RV64_DEFS_V__
// ============================================================================
// File: regfile.v
// Description: 32 x 64-bit Register File with internal WB->ID forwarding
// Standard Verilog-2001
// ============================================================================


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
// ============================================================================
// File: alu.v
// Description: 64-bit RV64I Arithmetic Logic Unit (ALU)
// Supports full 64-bit operations and 32-bit W-instructions
// Standard Verilog-2001
// ============================================================================


module alu (
    input  wire [`XLEN-1:0]      opa,
    input  wire [`XLEN-1:0]      opb,
    input  wire [4:0]            alu_ctrl,
    output reg  [`XLEN-1:0]      result,
    output wire                  zero
);

    wire signed [`XLEN-1:0] signed_opa = opa;
    wire signed [`XLEN-1:0] signed_opb = opb;

    // 32-bit slices for W-instructions
    wire [31:0] opa32 = opa[31:0];
    wire [31:0] opb32 = opb[31:0];
    wire signed [31:0] signed_opa32 = opa[31:0];

    reg [31:0] res32;

    always @(*) begin
        res32 = 32'd0;
        case (alu_ctrl)
            `ALU_ADD:    result = opa + opb;
            `ALU_SUB:    result = opa - opb;
            `ALU_SLL:    result = opa << opb[5:0];
            `ALU_SLT:    result = (signed_opa < signed_opb) ? 64'd1 : 64'd0;
            `ALU_SLTU:   result = (opa < opb) ? 64'd1 : 64'd0;
            `ALU_XOR:    result = opa ^ opb;
            `ALU_SRL:    result = opa >> opb[5:0];
            `ALU_SRA:    result = signed_opa >>> opb[5:0];
            `ALU_OR:     result = opa | opb;
            `ALU_AND:    result = opa & opb;

            // 32-bit W-instructions (truncated to 32 bits, then sign-extended to 64 bits)
            `ALU_ADDW: begin
                res32  = opa32 + opb32;
                result = {{32{res32[31]}}, res32};
            end
            `ALU_SUBW: begin
                res32  = opa32 - opb32;
                result = {{32{res32[31]}}, res32};
            end
            `ALU_SLLW: begin
                res32  = opa32 << opb32[4:0];
                result = {{32{res32[31]}}, res32};
            end
            `ALU_SRLW: begin
                res32  = opa32 >> opb32[4:0];
                result = {{32{res32[31]}}, res32};
            end
            `ALU_SRAW: begin
                res32  = signed_opa32 >>> opb32[4:0];
                result = {{32{res32[31]}}, res32};
            end

            `ALU_PASS_B: result = opb;

            default:     result = {`XLEN{1'b0}};
        endcase
    end

    assign zero = (result == {`XLEN{1'b0}});

endmodule
// ============================================================================
// File: branch_cond.v
// Description: Branch condition comparator for RV64 conditional branches
// Standard Verilog-2001
// ============================================================================


module branch_cond (
    input  wire [`XLEN-1:0]      rdata1,
    input  wire [`XLEN-1:0]      rdata2,
    input  wire [2:0]            funct3,
    output reg                   taken
);

    wire signed [`XLEN-1:0] signed_r1 = rdata1;
    wire signed [`XLEN-1:0] signed_r2 = rdata2;

    always @(*) begin
        case (funct3)
            `FUNCT3_BEQ:  taken = (rdata1 == rdata2);
            `FUNCT3_BNE:  taken = (rdata1 != rdata2);
            `FUNCT3_BLT:  taken = (signed_r1 < signed_r2);
            `FUNCT3_BGE:  taken = (signed_r1 >= signed_r2);
            `FUNCT3_BLTU: taken = (rdata1 < rdata2);
            `FUNCT3_BGEU: taken = (rdata1 >= rdata2);
            default:      taken = 1'b0;
        endcase
    end

endmodule
// ============================================================================
// File: forwarding_unit.v
// Description: Data hazard forwarding unit (EX/MEM and MEM/WB forwarding to EX)
// Standard Verilog-2001
// ============================================================================


module forwarding_unit (
    // Source registers from ID/EX stage
    input  wire [4:0]  id_ex_rs1,
    input  wire [4:0]  id_ex_rs2,

    // Destination register and write enable from EX/MEM stage
    input  wire [4:0]  ex_mem_rd,
    input  wire        ex_mem_reg_write,

    // Destination register and write enable from MEM/WB stage
    input  wire [4:0]  mem_wb_rd,
    input  wire        mem_wb_reg_write,

    // Forwarding select signals to EX stage
    output reg  [1:0]  forward_a,
    output reg  [1:0]  forward_b
);

    // Forwarding for Operand A (rs1)
    always @(*) begin
        // Priority 1: EX/MEM hazard (most recent instruction)
        if (ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs1)) begin
            forward_a = `FWD_FROM_EX; // 2'b10
        end
        // Priority 2: MEM/WB hazard (older instruction)
        else if (mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs1)) begin
            forward_a = `FWD_FROM_MEM; // 2'b01
        end
        // No hazard
        else begin
            forward_a = `FWD_NONE; // 2'b00
        end
    end

    // Forwarding for Operand B (rs2)
    always @(*) begin
        // Priority 1: EX/MEM hazard
        if (ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs2)) begin
            forward_b = `FWD_FROM_EX; // 2'b10
        end
        // Priority 2: MEM/WB hazard
        else if (mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs2)) begin
            forward_b = `FWD_FROM_MEM; // 2'b01
        end
        // No hazard
        else begin
            forward_b = `FWD_NONE; // 2'b00
        end
    end

endmodule
// ============================================================================
// File: hazard_detection.v
// Description: Hazard detection unit for Load-Use stalls and Control hazard flushes
// Standard Verilog-2001
// ============================================================================


module hazard_detection (
    // Instruction currently in ID stage
    input  wire [4:0]  if_id_rs1,
    input  wire [4:0]  if_id_rs2,
    input  wire        if_id_uses_rs1,
    input  wire        if_id_uses_rs2,

    // Instruction currently in EX stage
    input  wire [4:0]  id_ex_rd,
    input  wire        id_ex_mem_read, // 1 if instruction in EX is a LOAD

    // Control hazard signal from EX stage (branch taken or jump)
    input  wire        branch_taken,

    // Stall and flush control outputs
    output reg         stall_pc,
    output reg         stall_if_id,
    output reg         flush_if_id,
    output reg         flush_id_ex
);

    wire load_use_hazard;

    // Load-use hazard detection:
    // If instruction in EX is a LOAD, and instruction in ID reads that destination register
    assign load_use_hazard = id_ex_mem_read && (id_ex_rd != 5'd0) &&
                            ((if_id_uses_rs1 && (id_ex_rd == if_id_rs1)) ||
                             (if_id_uses_rs2 && (id_ex_rd == if_id_rs2)));

    always @(*) begin
        // Default: no stalls, no flushes
        stall_pc    = 1'b0;
        stall_if_id = 1'b0;
        flush_if_id = 1'b0;
        flush_id_ex = 1'b0;

        // Control hazard (Branch taken / Jump in EX stage) has highest priority:
        // Crushes the 2 speculative instructions in IF/ID and ID/EX!
        if (branch_taken) begin
            flush_if_id = 1'b1;
            flush_id_ex = 1'b1;
        end
        // Data hazard: Load-use stall (1 cycle bubble)
        else if (load_use_hazard) begin
            stall_pc    = 1'b1; // Freeze PC
            stall_if_id = 1'b1; // Freeze IF/ID
            flush_id_ex = 1'b1; // Insert NOP bubble into ID/EX
        end
    end

endmodule
// ============================================================================
// File: if_stage.v
// Description: Instruction Fetch (IF) stage for RV64
// Standard Verilog-2001
// ============================================================================


module if_stage (
    input  wire                  clk,
    input  wire                  rst,

    // Hazard / Control signals
    input  wire                  stall_pc,
    input  wire                  branch_taken,
    input  wire [`XLEN-1:0]      branch_target,

    // Instruction memory interface
    output wire [`XLEN-1:0]      imem_addr,
    
    // Outputs to IF/ID pipeline register
    output reg  [`XLEN-1:0]      pc,
    output wire [`XLEN-1:0]      pc_plus_4
);

    wire [`XLEN-1:0] next_pc;

    assign pc_plus_4 = pc + 64'd4;
    assign next_pc   = branch_taken ? branch_target : pc_plus_4;
    assign imem_addr = pc;

    always @(posedge clk) begin
        if (rst) begin
            pc <= {`XLEN{1'b0}};
        end else if (!stall_pc) begin
            pc <= next_pc;
        end
    end

endmodule
// ============================================================================
// File: id_stage.v
// Description: Instruction Decode (ID) stage and immediate generator
// Standard Verilog-2001
// ============================================================================


module id_stage (
    input  wire                  clk,
    input  wire                  rst,

    // Instruction and PC from IF/ID
    input  wire [`ILEN-1:0]      inst,
    input  wire [`XLEN-1:0]      pc,

    // Writeback interface from WB stage
    input  wire                  wb_wen,
    input  wire [4:0]            wb_waddr,
    input  wire [`XLEN-1:0]      wb_wdata,

    // Register file outputs
    output wire [4:0]            rs1,
    output wire [4:0]            rs2,
    output wire [4:0]            rd,
    output wire [`XLEN-1:0]      rdata1,
    output wire [`XLEN-1:0]      rdata2,
    output reg  [`XLEN-1:0]      imm,

    // Usage flags for hazard detection
    output reg                   uses_rs1,
    output reg                   uses_rs2,

    // Control signals to EX stage
    output reg  [4:0]            alu_ctrl,
    output reg                   alua_sel,
    output reg                   alub_sel,
    output reg                   branch,
    output reg                   jal,
    output reg                   jalr,
    output reg                   mem_read,
    output reg                   mem_write,
    output reg                   reg_write,
    output reg  [1:0]            wb_sel,
    output wire [2:0]            funct3,
    output reg                   halt
);

    wire [6:0] opcode = inst[6:0];
    assign funct3     = inst[14:12];
    wire [6:0] funct7 = inst[31:25];

    assign rs1 = inst[19:15];
    assign rs2 = inst[24:20];
    assign rd  = inst[11:7];

    // Instantiate Register File
    regfile rf (
        .clk    (clk),
        .rst    (rst),
        .raddr1 (rs1),
        .rdata1 (rdata1),
        .raddr2 (rs2),
        .rdata2 (rdata2),
        .wen    (wb_wen),
        .waddr  (wb_waddr),
        .wdata  (wb_wdata)
    );

    // Immediate Generation (Sign-extended to 64 bits)
    always @(*) begin
        case (opcode)
            `OPCODE_I_OP,
            `OPCODE_I_OP_32,
            `OPCODE_LOAD,
            `OPCODE_JALR: begin
                imm = {{52{inst[31]}}, inst[31:20]};
            end
            `OPCODE_STORE: begin
                imm = {{52{inst[31]}}, inst[31:25], inst[11:7]};
            end
            `OPCODE_BRANCH: begin
                imm = {{52{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};
            end
            `OPCODE_LUI,
            `OPCODE_AUIPC: begin
                // In RV64, LUI and AUIPC sign-extend the 20-bit immediate shifted by 12
                imm = {{32{inst[31]}}, inst[31:12], 12'b0};
            end
            `OPCODE_JAL: begin
                imm = {{44{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0};
            end
            default: begin
                imm = {`XLEN{1'b0}};
            end
        endcase
    end

    // Control Unit Decoder
    always @(*) begin
        // Defaults
        alua_sel   = `ALUA_SEL_RS1;
        alub_sel   = `ALUB_SEL_RS2;
        alu_ctrl   = `ALU_ADD;
        branch     = 1'b0;
        jal        = 1'b0;
        jalr       = 1'b0;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        reg_write  = 1'b0;
        wb_sel     = `WB_SEL_ALU;
        uses_rs1   = 1'b0;
        uses_rs2   = 1'b0;
        halt       = 1'b0;

        case (opcode)
            // 64-bit Register-Register Operations
            `OPCODE_R_OP: begin
                alua_sel   = `ALUA_SEL_RS1;
                alub_sel   = `ALUB_SEL_RS2;
                reg_write  = 1'b1;
                wb_sel     = `WB_SEL_ALU;
                uses_rs1   = 1'b1;
                uses_rs2   = 1'b1;
                case (funct3)
                    3'b000: alu_ctrl = (funct7[5]) ? `ALU_SUB : `ALU_ADD;
                    3'b001: alu_ctrl = `ALU_SLL;
                    3'b010: alu_ctrl = `ALU_SLT;
                    3'b011: alu_ctrl = `ALU_SLTU;
                    3'b100: alu_ctrl = `ALU_XOR;
                    3'b101: alu_ctrl = (funct7[5]) ? `ALU_SRA : `ALU_SRL;
                    3'b110: alu_ctrl = `ALU_OR;
                    3'b111: alu_ctrl = `ALU_AND;
                    default: alu_ctrl = `ALU_ADD;
                endcase
            end

            // 32-bit Register-Register Operations (W-instructions)
            `OPCODE_R_OP_32: begin
                alua_sel   = `ALUA_SEL_RS1;
                alub_sel   = `ALUB_SEL_RS2;
                reg_write  = 1'b1;
                wb_sel     = `WB_SEL_ALU;
                uses_rs1   = 1'b1;
                uses_rs2   = 1'b1;
                case (funct3)
                    3'b000: alu_ctrl = (funct7[5]) ? `ALU_SUBW : `ALU_ADDW;
                    3'b001: alu_ctrl = `ALU_SLLW;
                    3'b101: alu_ctrl = (funct7[5]) ? `ALU_SRAW : `ALU_SRLW;
                    default: alu_ctrl = `ALU_ADDW;
                endcase
            end

            // 64-bit Register-Immediate Operations
            `OPCODE_I_OP: begin
                alua_sel   = `ALUA_SEL_RS1;
                alub_sel   = `ALUB_SEL_IMM;
                reg_write  = 1'b1;
                wb_sel     = `WB_SEL_ALU;
                uses_rs1   = 1'b1;
                case (funct3)
                    3'b000: alu_ctrl = `ALU_ADD; // ADDI
                    3'b010: alu_ctrl = `ALU_SLT; // SLTI
                    3'b011: alu_ctrl = `ALU_SLTU;// SLTIU
                    3'b100: alu_ctrl = `ALU_XOR; // XORI
                    3'b110: alu_ctrl = `ALU_OR;  // ORI
                    3'b111: alu_ctrl = `ALU_AND; // ANDI
                    3'b001: alu_ctrl = `ALU_SLL; // SLLI
                    3'b101: alu_ctrl = (inst[30]) ? `ALU_SRA : `ALU_SRL; // SRAI / SRLI
                    default: alu_ctrl = `ALU_ADD;
                endcase
            end

            // 32-bit Register-Immediate Operations (W-instructions)
            `OPCODE_I_OP_32: begin
                alua_sel   = `ALUA_SEL_RS1;
                alub_sel   = `ALUB_SEL_IMM;
                reg_write  = 1'b1;
                wb_sel     = `WB_SEL_ALU;
                uses_rs1   = 1'b1;
                case (funct3)
                    3'b000: alu_ctrl = `ALU_ADDW; // ADDIW
                    3'b001: alu_ctrl = `ALU_SLLW; // SLLIW
                    3'b101: alu_ctrl = (inst[30]) ? `ALU_SRAW : `ALU_SRLW; // SRAIW / SRLIW
                    default: alu_ctrl = `ALU_ADDW;
                endcase
            end

            // LOAD Instructions
            `OPCODE_LOAD: begin
                alua_sel   = `ALUA_SEL_RS1;
                alub_sel   = `ALUB_SEL_IMM;
                alu_ctrl   = `ALU_ADD;
                mem_read   = 1'b1;
                reg_write  = 1'b1;
                wb_sel     = `WB_SEL_MEM;
                uses_rs1   = 1'b1;
            end

            // STORE Instructions
            `OPCODE_STORE: begin
                alua_sel   = `ALUA_SEL_RS1;
                alub_sel   = `ALUB_SEL_IMM;
                alu_ctrl   = `ALU_ADD;
                mem_write  = 1'b1;
                uses_rs1   = 1'b1;
                uses_rs2   = 1'b1;
            end

            // Conditional BRANCH
            `OPCODE_BRANCH: begin
                alua_sel   = `ALUA_SEL_PC;
                alub_sel   = `ALUB_SEL_IMM;
                alu_ctrl   = `ALU_ADD; // Computes branch target PC + imm
                branch     = 1'b1;
                uses_rs1   = 1'b1;
                uses_rs2   = 1'b1;
            end

            // JAL (Jump and Link)
            `OPCODE_JAL: begin
                alua_sel   = `ALUA_SEL_PC;
                alub_sel   = `ALUB_SEL_IMM;
                alu_ctrl   = `ALU_ADD; // Computes jump target PC + imm
                jal        = 1'b1;
                reg_write  = 1'b1;
                wb_sel     = `WB_SEL_PC4;
            end

            // JALR (Jump and Link Register)
            `OPCODE_JALR: begin
                alua_sel   = `ALUA_SEL_RS1;
                alub_sel   = `ALUB_SEL_IMM;
                alu_ctrl   = `ALU_ADD; // Computes jump target rs1 + imm
                jalr       = 1'b1;
                reg_write  = 1'b1;
                wb_sel     = `WB_SEL_PC4;
                uses_rs1   = 1'b1;
            end

            // LUI (Load Upper Immediate)
            `OPCODE_LUI: begin
                alub_sel   = `ALUB_SEL_IMM;
                alu_ctrl   = `ALU_PASS_B;
                reg_write  = 1'b1;
                wb_sel     = `WB_SEL_ALU;
            end

            // AUIPC (Add Upper Immediate to PC)
            `OPCODE_AUIPC: begin
                alua_sel   = `ALUA_SEL_PC;
                alub_sel   = `ALUB_SEL_IMM;
                alu_ctrl   = `ALU_ADD;
                reg_write  = 1'b1;
                wb_sel     = `WB_SEL_ALU;
            end

            // SYSTEM (WFI / Halt)
            `OPCODE_SYSTEM: begin
                if (inst == `WFI_INST) begin
                    halt = 1'b1;
                end
            end

            default: begin
                // Invalid or unsupported instruction defaults to NOP
            end
        endcase
    end

endmodule
// ============================================================================
// File: ex_stage.v
// Description: Execution (EX) stage with forwarding muxes, ALU, and branch logic
// Standard Verilog-2001
// ============================================================================


module ex_stage (
    // Inputs from ID/EX pipeline register
    input  wire [`XLEN-1:0]      pc,
    input  wire [`XLEN-1:0]      pc_plus_4,
    input  wire [`XLEN-1:0]      rdata1,
    input  wire [`XLEN-1:0]      rdata2,
    input  wire [`XLEN-1:0]      imm,
    input  wire [4:0]            alu_ctrl,
    input  wire                  alua_sel,
    input  wire                  alub_sel,
    input  wire                  branch,
    input  wire                  jal,
    input  wire                  jalr,
    input  wire [2:0]            funct3,

    // Forwarding inputs
    input  wire [1:0]            forward_a,
    input  wire [1:0]            forward_b,
    input  wire [`XLEN-1:0]      fwd_data_ex,  // From EX/MEM stage
    input  wire [`XLEN-1:0]      fwd_data_mem, // From MEM/WB stage

    // Execution outputs
    output wire [`XLEN-1:0]      alu_result,
    output wire [`XLEN-1:0]      store_data,
    output wire                  branch_taken,
    output reg  [`XLEN-1:0]      branch_target
);

    // Forwarding Muxes for source operands
    reg [`XLEN-1:0] op1_forwarded;
    reg [`XLEN-1:0] op2_forwarded;

    always @(*) begin
        case (forward_a)
            `FWD_FROM_EX:  op1_forwarded = fwd_data_ex;
            `FWD_FROM_MEM: op1_forwarded = fwd_data_mem;
            default:       op1_forwarded = rdata1;
        endcase
    end

    always @(*) begin
        case (forward_b)
            `FWD_FROM_EX:  op2_forwarded = fwd_data_ex;
            `FWD_FROM_MEM: op2_forwarded = fwd_data_mem;
            default:       op2_forwarded = rdata2;
        endcase
    end

    // ALU input selection
    wire [`XLEN-1:0] alu_opa = (alua_sel == `ALUA_SEL_PC) ? pc : op1_forwarded;
    wire [`XLEN-1:0] alu_opb = (alub_sel == `ALUB_SEL_IMM) ? imm : op2_forwarded;

    // Store data is the forwarded rs2 value
    assign store_data = op2_forwarded;

    // Instantiate 64-bit ALU
    wire alu_zero;
    alu alu_inst (
        .opa      (alu_opa),
        .opb      (alu_opb),
        .alu_ctrl (alu_ctrl),
        .result   (alu_result),
        .zero     (alu_zero)
    );

    // Branch condition comparator
    wire cond_taken;
    branch_cond br_cond_inst (
        .rdata1 (op1_forwarded),
        .rdata2 (op2_forwarded),
        .funct3 (funct3),
        .taken  (cond_taken)
    );

    // Control hazard decision (branch taken or jump)
    assign branch_taken = (branch && cond_taken) || jal || jalr;

    // Target PC calculation
    always @(*) begin
        if (jalr) begin
            // JALR target is (rs1 + imm) with least-significant bit cleared
            branch_target = (op1_forwarded + imm) & ~64'd1;
        end else begin
            // Branch and JAL target is PC + imm
            branch_target = pc + imm;
        end
    end

endmodule
// ============================================================================
// File: mem_stage.v
// Description: Memory (MEM) stage for RV64 load/store alignment & sign-extension
// Standard Verilog-2001
// ============================================================================


module mem_stage (
    // Inputs from EX/MEM pipeline register
    input  wire [`XLEN-1:0]      alu_result,
    input  wire [`XLEN-1:0]      store_data,
    input  wire [2:0]            funct3,
    input  wire                  mem_read,
    input  wire                  mem_write,

    // Data memory interface
    output wire [`XLEN-1:0]      dmem_addr,
    output reg  [`XLEN-1:0]      dmem_wdata,
    output reg  [7:0]            dmem_byte_en,
    output wire                  dmem_en,
    output wire                  dmem_wen,
    input  wire [`XLEN-1:0]      dmem_rdata,

    // Formatted load data to MEM/WB register
    output reg  [`XLEN-1:0]      load_data
);

    wire [2:0] offset = alu_result[2:0];

    // Memory address (full address passed to interconnect / MMIO)
    assign dmem_addr = alu_result;
    assign dmem_en   = mem_read | mem_write;
    assign dmem_wen  = mem_write;

    // Store formatting: byte enable generation and data alignment
    always @(*) begin
        dmem_byte_en = 8'b00000000;
        dmem_wdata   = {`XLEN{1'b0}};

        if (mem_write) begin
            case (funct3)
                `FUNCT3_SB: begin
                    dmem_byte_en = 8'b00000001 << offset;
                    dmem_wdata   = store_data[7:0] << (offset * 8);
                end
                `FUNCT3_SH: begin
                    dmem_byte_en = 8'b00000011 << (offset & 3'b110);
                    dmem_wdata   = store_data[15:0] << ((offset & 3'b110) * 8);
                end
                `FUNCT3_SW: begin
                    dmem_byte_en = offset[2] ? 8'b11110000 : 8'b00001111;
                    dmem_wdata   = offset[2] ? {store_data[31:0], 32'd0} : {32'd0, store_data[31:0]};
                end
                `FUNCT3_SD: begin
                    dmem_byte_en = 8'b11111111;
                    dmem_wdata   = store_data;
                end
                default: begin
                    dmem_byte_en = 8'b00000000;
                    dmem_wdata   = {`XLEN{1'b0}};
                end
            endcase
        end
    end

    // Load formatting: extraction and sign/zero extension
    reg [7:0]  selected_byte;
    reg [15:0] selected_half;
    reg [31:0] selected_word;

    always @(*) begin
        // Byte slice
        case (offset)
            3'd0: selected_byte = dmem_rdata[7:0];
            3'd1: selected_byte = dmem_rdata[15:8];
            3'd2: selected_byte = dmem_rdata[23:16];
            3'd3: selected_byte = dmem_rdata[31:24];
            3'd4: selected_byte = dmem_rdata[39:32];
            3'd5: selected_byte = dmem_rdata[47:40];
            3'd6: selected_byte = dmem_rdata[55:48];
            3'd7: selected_byte = dmem_rdata[63:56];
        endcase

        // Halfword slice (aligned to 2 bytes)
        case (offset[2:1])
            2'd0: selected_half = dmem_rdata[15:0];
            2'd1: selected_half = dmem_rdata[31:16];
            2'd2: selected_half = dmem_rdata[47:32];
            2'd3: selected_half = dmem_rdata[63:48];
        endcase

        // Word slice (aligned to 4 bytes)
        selected_word = offset[2] ? dmem_rdata[63:32] : dmem_rdata[31:0];

        // Format final load data based on funct3
        case (funct3)
            `FUNCT3_LB:  load_data = {{56{selected_byte[7]}}, selected_byte};
            `FUNCT3_LBU: load_data = {56'd0, selected_byte};
            `FUNCT3_LH:  load_data = {{48{selected_half[15]}}, selected_half};
            `FUNCT3_LHU: load_data = {48'd0, selected_half};
            `FUNCT3_LW:  load_data = {{32{selected_word[31]}}, selected_word};
            `FUNCT3_LWU: load_data = {32'd0, selected_word};
            `FUNCT3_LD:  load_data = dmem_rdata;
            default:     load_data = dmem_rdata;
        endcase
    end

endmodule
// ============================================================================
// File: wb_stage.v
// Description: Writeback (WB) stage multiplexer
// Standard Verilog-2001
// ============================================================================


module wb_stage (
    input  wire [`XLEN-1:0] alu_result,
    input  wire [`XLEN-1:0] load_data,
    input  wire [`XLEN-1:0] pc_plus_4,
    input  wire [1:0]       wb_sel,
    output reg  [`XLEN-1:0] wb_data
);

    always @(*) begin
        case (wb_sel)
            `WB_SEL_ALU: wb_data = alu_result;
            `WB_SEL_MEM: wb_data = load_data;
            `WB_SEL_PC4: wb_data = pc_plus_4;
            default:     wb_data = alu_result;
        endcase
    end

endmodule
// ============================================================================
// File: pipeline_registers.v
// Description: IF/ID, ID/EX, EX/MEM, and MEM/WB pipeline registers
// Standard Verilog-2001
// ============================================================================


// ----------------------------------------------------------------------------
// 1. IF/ID Pipeline Register
// ----------------------------------------------------------------------------
module if_id_reg (
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  stall,
    input  wire                  flush,

    input  wire [`XLEN-1:0]      pc_in,
    input  wire [`XLEN-1:0]      pc_plus_4_in,
    input  wire [`ILEN-1:0]      inst_in,

    output reg  [`XLEN-1:0]      pc_out,
    output reg  [`XLEN-1:0]      pc_plus_4_out,
    output reg  [`ILEN-1:0]      inst_out
);

    always @(posedge clk) begin
        if (rst || flush) begin
            pc_out        <= {`XLEN{1'b0}};
            pc_plus_4_out <= {`XLEN{1'b0}};
            inst_out      <= `NOP_INST; // Insert NOP on flush or reset
        end else if (!stall) begin
            pc_out        <= pc_in;
            pc_plus_4_out <= pc_plus_4_in;
            inst_out      <= inst_in;
        end
    end

endmodule

// ----------------------------------------------------------------------------
// 2. ID/EX Pipeline Register
// ----------------------------------------------------------------------------
module id_ex_reg (
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  flush,

    // Data inputs
    input  wire [`XLEN-1:0]      pc_in,
    input  wire [`XLEN-1:0]      pc_plus_4_in,
    input  wire [`XLEN-1:0]      rdata1_in,
    input  wire [`XLEN-1:0]      rdata2_in,
    input  wire [`XLEN-1:0]      imm_in,
    input  wire [4:0]            rs1_in,
    input  wire [4:0]            rs2_in,
    input  wire [4:0]            rd_in,

    // Control inputs
    input  wire [4:0]            alu_ctrl_in,
    input  wire                  alua_sel_in,
    input  wire                  alub_sel_in,
    input  wire                  branch_in,
    input  wire                  jal_in,
    input  wire                  jalr_in,
    input  wire                  mem_read_in,
    input  wire                  mem_write_in,
    input  wire                  reg_write_in,
    input  wire [1:0]            wb_sel_in,
    input  wire [2:0]            funct3_in,
    input  wire                  halt_in,

    // Data outputs
    output reg  [`XLEN-1:0]      pc_out,
    output reg  [`XLEN-1:0]      pc_plus_4_out,
    output reg  [`XLEN-1:0]      rdata1_out,
    output reg  [`XLEN-1:0]      rdata2_out,
    output reg  [`XLEN-1:0]      imm_out,
    output reg  [4:0]            rs1_out,
    output reg  [4:0]            rs2_out,
    output reg  [4:0]            rd_out,

    // Control outputs
    output reg  [4:0]            alu_ctrl_out,
    output reg                  alua_sel_out,
    output reg                  alub_sel_out,
    output reg                  branch_out,
    output reg                  jal_out,
    output reg                  jalr_out,
    output reg                  mem_read_out,
    output reg                  mem_write_out,
    output reg                  reg_write_out,
    output reg  [1:0]            wb_sel_out,
    output reg  [2:0]            funct3_out,
    output reg                  halt_out
);

    always @(posedge clk) begin
        if (rst || flush) begin
            pc_out        <= {`XLEN{1'b0}};
            pc_plus_4_out <= {`XLEN{1'b0}};
            rdata1_out    <= {`XLEN{1'b0}};
            rdata2_out    <= {`XLEN{1'b0}};
            imm_out       <= {`XLEN{1'b0}};
            rs1_out       <= 5'd0;
            rs2_out       <= 5'd0;
            rd_out        <= 5'd0;

            alu_ctrl_out  <= `ALU_ADD;
            alua_sel_out  <= `ALUA_SEL_RS1;
            alub_sel_out  <= `ALUB_SEL_RS2;
            branch_out    <= 1'b0;
            jal_out       <= 1'b0;
            jalr_out      <= 1'b0;
            mem_read_out  <= 1'b0;
            mem_write_out <= 1'b0;
            reg_write_out <= 1'b0;
            wb_sel_out    <= `WB_SEL_ALU;
            funct3_out    <= 3'd0;
            halt_out      <= 1'b0;
        end else begin
            pc_out        <= pc_in;
            pc_plus_4_out <= pc_plus_4_in;
            rdata1_out    <= rdata1_in;
            rdata2_out    <= rdata2_in;
            imm_out       <= imm_in;
            rs1_out       <= rs1_in;
            rs2_out       <= rs2_in;
            rd_out        <= rd_in;

            alu_ctrl_out  <= alu_ctrl_in;
            alua_sel_out  <= alua_sel_in;
            alub_sel_out  <= alub_sel_in;
            branch_out    <= branch_in;
            jal_out       <= jal_in;
            jalr_out      <= jalr_in;
            mem_read_out  <= mem_read_in;
            mem_write_out <= mem_write_in;
            reg_write_out <= reg_write_in;
            wb_sel_out    <= wb_sel_in;
            funct3_out    <= funct3_in;
            halt_out      <= halt_in;
        end
    end

endmodule

// ----------------------------------------------------------------------------
// 3. EX/MEM Pipeline Register
// ----------------------------------------------------------------------------
module ex_mem_reg (
    input  wire                  clk,
    input  wire                  rst,

    // Data inputs
    input  wire [`XLEN-1:0]      alu_result_in,
    input  wire [`XLEN-1:0]      store_data_in,
    input  wire [4:0]            rd_in,
    input  wire [`XLEN-1:0]      pc_plus_4_in,

    // Control inputs
    input  wire                  mem_read_in,
    input  wire                  mem_write_in,
    input  wire                  reg_write_in,
    input  wire [1:0]            wb_sel_in,
    input  wire [2:0]            funct3_in,
    input  wire                  halt_in,

    // Data outputs
    output reg  [`XLEN-1:0]      alu_result_out,
    output reg  [`XLEN-1:0]      store_data_out,
    output reg  [4:0]            rd_out,
    output reg  [`XLEN-1:0]      pc_plus_4_out,

    // Control outputs
    output reg                  mem_read_out,
    output reg                  mem_write_out,
    output reg                  reg_write_out,
    output reg  [1:0]            wb_sel_out,
    output reg  [2:0]            funct3_out,
    output reg                  halt_out
);

    always @(posedge clk) begin
        if (rst) begin
            alu_result_out <= {`XLEN{1'b0}};
            store_data_out <= {`XLEN{1'b0}};
            rd_out         <= 5'd0;
            pc_plus_4_out  <= {`XLEN{1'b0}};

            mem_read_out   <= 1'b0;
            mem_write_out  <= 1'b0;
            reg_write_out  <= 1'b0;
            wb_sel_out     <= `WB_SEL_ALU;
            funct3_out     <= 3'd0;
            halt_out       <= 1'b0;
        end else begin
            alu_result_out <= alu_result_in;
            store_data_out <= store_data_in;
            rd_out         <= rd_in;
            pc_plus_4_out  <= pc_plus_4_in;

            mem_read_out   <= mem_read_in;
            mem_write_out  <= mem_write_in;
            reg_write_out  <= reg_write_in;
            wb_sel_out     <= wb_sel_in;
            funct3_out     <= funct3_in;
            halt_out       <= halt_in;
        end
    end

endmodule

// ----------------------------------------------------------------------------
// 4. MEM/WB Pipeline Register
// ----------------------------------------------------------------------------
module mem_wb_reg (
    input  wire                  clk,
    input  wire                  rst,

    // Data inputs
    input  wire [`XLEN-1:0]      alu_result_in,
    input  wire [`XLEN-1:0]      load_data_in,
    input  wire [4:0]            rd_in,
    input  wire [`XLEN-1:0]      pc_plus_4_in,

    // Control inputs
    input  wire                  reg_write_in,
    input  wire [1:0]            wb_sel_in,
    input  wire                  halt_in,

    // Data outputs
    output reg  [`XLEN-1:0]      alu_result_out,
    output reg  [`XLEN-1:0]      load_data_out,
    output reg  [4:0]            rd_out,
    output reg  [`XLEN-1:0]      pc_plus_4_out,

    // Control outputs
    output reg                  reg_write_out,
    output reg  [1:0]            wb_sel_out,
    output reg                  halt_out
);

    always @(posedge clk) begin
        if (rst) begin
            alu_result_out <= {`XLEN{1'b0}};
            load_data_out  <= {`XLEN{1'b0}};
            rd_out         <= 5'd0;
            pc_plus_4_out  <= {`XLEN{1'b0}};

            reg_write_out  <= 1'b0;
            wb_sel_out     <= `WB_SEL_ALU;
            halt_out       <= 1'b0;
        end else begin
            alu_result_out <= alu_result_in;
            load_data_out  <= load_data_in;
            rd_out         <= rd_in;
            pc_plus_4_out  <= pc_plus_4_in;

            reg_write_out  <= reg_write_in;
            wb_sel_out     <= wb_sel_in;
            halt_out       <= halt_in;
        end
    end

endmodule
// ============================================================================
// File: core_top.v
// Description: Top-level 5-stage In-Order RV64I Pipelined Processor Core
// Standard Verilog-2001
// ============================================================================


module core_top (
    input  wire                  clk,
    input  wire                  rst,

    // Instruction Memory Interface (Read-only, 32-bit instructions)
    output wire [`XLEN-1:0]      imem_addr,
    input  wire [`ILEN-1:0]      imem_rdata,

    // Data Memory Interface (Read/Write, 64-bit doublewords)
    output wire [`XLEN-1:0]      dmem_addr,
    output wire [`XLEN-1:0]      dmem_wdata,
    output wire [7:0]            dmem_byte_en,
    output wire                  dmem_en,
    output wire                  dmem_wen,
    input  wire [`XLEN-1:0]      dmem_rdata,

    // Performance & Status outputs
    output wire                  halted,
    output reg  [31:0]           cycle_count,
    output reg  [31:0]           retired_inst_count
);

    // ========================================================================
    // Internal Wires & Interconnects
    // ========================================================================

    // Hazard Detection Signals
    wire stall_pc;
    wire stall_if_id;
    wire flush_if_id;
    wire flush_id_ex;

    // Forwarding Signals
    wire [1:0] forward_a;
    wire [1:0] forward_b;

    // Branch / Jump Signals from EX
    wire                  branch_taken;
    wire [`XLEN-1:0]      branch_target;

    // IF Stage Outputs
    wire [`XLEN-1:0]      if_pc;
    wire [`XLEN-1:0]      if_pc_plus_4;

    // IF/ID Register Outputs
    wire [`XLEN-1:0]      if_id_pc;
    wire [`XLEN-1:0]      if_id_pc_plus_4;
    wire [`ILEN-1:0]      if_id_inst;

    // ID Stage Outputs
    wire [4:0]            id_rs1;
    wire [4:0]            id_rs2;
    wire [4:0]            id_rd;
    wire [`XLEN-1:0]      id_rdata1;
    wire [`XLEN-1:0]      id_rdata2;
    wire [`XLEN-1:0]      id_imm;
    wire                  id_uses_rs1;
    wire                  id_uses_rs2;
    wire [4:0]            id_alu_ctrl;
    wire                  id_alua_sel;
    wire                  id_alub_sel;
    wire                  id_branch;
    wire                  id_jal;
    wire                  id_jalr;
    wire                  id_mem_read;
    wire                  id_mem_write;
    wire                  id_reg_write;
    wire [1:0]            id_wb_sel;
    wire [2:0]            id_funct3;
    wire                  id_halt;

    // ID/EX Register Outputs
    wire [`XLEN-1:0]      id_ex_pc;
    wire [`XLEN-1:0]      id_ex_pc_plus_4;
    wire [`XLEN-1:0]      id_ex_rdata1;
    wire [`XLEN-1:0]      id_ex_rdata2;
    wire [`XLEN-1:0]      id_ex_imm;
    wire [4:0]            id_ex_rs1;
    wire [4:0]            id_ex_rs2;
    wire [4:0]            id_ex_rd;
    wire [4:0]            id_ex_alu_ctrl;
    wire                  id_ex_alua_sel;
    wire                  id_ex_alub_sel;
    wire                  id_ex_branch;
    wire                  id_ex_jal;
    wire                  id_ex_jalr;
    wire                  id_ex_mem_read;
    wire                  id_ex_mem_write;
    wire                  id_ex_reg_write;
    wire [1:0]            id_ex_wb_sel;
    wire [2:0]            id_ex_funct3;
    wire                  id_ex_halt;

    // EX Stage Outputs
    wire [`XLEN-1:0]      ex_alu_result;
    wire [`XLEN-1:0]      ex_store_data;

    // EX/MEM Register Outputs
    wire [`XLEN-1:0]      ex_mem_alu_result;
    wire [`XLEN-1:0]      ex_mem_store_data;
    wire [4:0]            ex_mem_rd;
    wire [`XLEN-1:0]      ex_mem_pc_plus_4;
    wire                  ex_mem_mem_read;
    wire                  ex_mem_mem_write;
    wire                  ex_mem_reg_write;
    wire [1:0]            ex_mem_wb_sel;
    wire [2:0]            ex_mem_funct3;
    wire                  ex_mem_halt;

    // MEM Stage Outputs
    wire [`XLEN-1:0]      mem_load_data;

    // MEM/WB Register Outputs
    wire [`XLEN-1:0]      mem_wb_alu_result;
    wire [`XLEN-1:0]      mem_wb_load_data;
    wire [4:0]            mem_wb_rd;
    wire [`XLEN-1:0]      mem_wb_pc_plus_4;
    wire                  mem_wb_reg_write;
    wire [1:0]            mem_wb_wb_sel;
    wire                  mem_wb_halt;

    // WB Stage Output
    wire [`XLEN-1:0]      wb_data;

    // ========================================================================
    // 1. Instruction Fetch (IF) Stage & Pipeline Register
    // ========================================================================
    if_stage if_inst (
        .clk           (clk),
        .rst           (rst),
        .stall_pc      (stall_pc),
        .branch_taken  (branch_taken),
        .branch_target (branch_target),
        .imem_addr     (imem_addr),
        .pc            (if_pc),
        .pc_plus_4     (if_pc_plus_4)
    );

    if_id_reg if_id_reg_inst (
        .clk           (clk),
        .rst           (rst),
        .stall         (stall_if_id),
        .flush         (flush_if_id),
        .pc_in         (if_pc),
        .pc_plus_4_in  (if_pc_plus_4),
        .inst_in       (imem_rdata),
        .pc_out        (if_id_pc),
        .pc_plus_4_out (if_id_pc_plus_4),
        .inst_out      (if_id_inst)
    );

    // ========================================================================
    // 2. Instruction Decode (ID) Stage & Pipeline Register
    // ========================================================================
    id_stage id_inst (
        .clk           (clk),
        .rst           (rst),
        .inst          (if_id_inst),
        .pc            (if_id_pc),
        .wb_wen        (mem_wb_reg_write),
        .wb_waddr      (mem_wb_rd),
        .wb_wdata      (wb_data),
        .rs1           (id_rs1),
        .rs2           (id_rs2),
        .rd            (id_rd),
        .rdata1        (id_rdata1),
        .rdata2        (id_rdata2),
        .imm           (id_imm),
        .uses_rs1      (id_uses_rs1),
        .uses_rs2      (id_uses_rs2),
        .alu_ctrl      (id_alu_ctrl),
        .alua_sel      (id_alua_sel),
        .alub_sel      (id_alub_sel),
        .branch        (id_branch),
        .jal           (id_jal),
        .jalr          (id_jalr),
        .mem_read      (id_mem_read),
        .mem_write     (id_mem_write),
        .reg_write     (id_reg_write),
        .wb_sel        (id_wb_sel),
        .funct3        (id_funct3),
        .halt          (id_halt)
    );

    id_ex_reg id_ex_reg_inst (
        .clk           (clk),
        .rst           (rst),
        .flush         (flush_id_ex),
        .pc_in         (if_id_pc),
        .pc_plus_4_in  (if_id_pc_plus_4),
        .rdata1_in     (id_rdata1),
        .rdata2_in     (id_rdata2),
        .imm_in        (id_imm),
        .rs1_in        (id_rs1),
        .rs2_in        (id_rs2),
        .rd_in         (id_rd),
        .alu_ctrl_in   (id_alu_ctrl),
        .alua_sel_in   (id_alua_sel),
        .alub_sel_in   (id_alub_sel),
        .branch_in     (id_branch),
        .jal_in        (id_jal),
        .jalr_in       (id_jalr),
        .mem_read_in   (id_mem_read),
        .mem_write_in  (id_mem_write),
        .reg_write_in  (id_reg_write),
        .wb_sel_in     (id_wb_sel),
        .funct3_in     (id_funct3),
        .halt_in       (id_halt),
        .pc_out        (id_ex_pc),
        .pc_plus_4_out (id_ex_pc_plus_4),
        .rdata1_out    (id_ex_rdata1),
        .rdata2_out    (id_ex_rdata2),
        .imm_out       (id_ex_imm),
        .rs1_out       (id_ex_rs1),
        .rs2_out       (id_ex_rs2),
        .rd_out        (id_ex_rd),
        .alu_ctrl_out  (id_ex_alu_ctrl),
        .alua_sel_out  (id_ex_alua_sel),
        .alub_sel_out  (id_ex_alub_sel),
        .branch_out    (id_ex_branch),
        .jal_out       (id_ex_jal),
        .jalr_out      (id_ex_jalr),
        .mem_read_out  (id_ex_mem_read),
        .mem_write_out (id_ex_mem_write),
        .reg_write_out (id_ex_reg_write),
        .wb_sel_out    (id_ex_wb_sel),
        .funct3_out    (id_ex_funct3),
        .halt_out      (id_ex_halt)
    );

    // ========================================================================
    // 3. Hazard Detection & Forwarding Units
    // ========================================================================
    hazard_detection hazard_unit (
        .if_id_rs1      (id_rs1),
        .if_id_rs2      (id_rs2),
        .if_id_uses_rs1 (id_uses_rs1),
        .if_id_uses_rs2 (id_uses_rs2),
        .id_ex_rd       (id_ex_rd),
        .id_ex_mem_read (id_ex_mem_read),
        .branch_taken   (branch_taken),
        .stall_pc       (stall_pc),
        .stall_if_id    (stall_if_id),
        .flush_if_id    (flush_if_id),
        .flush_id_ex    (flush_id_ex)
    );

    forwarding_unit fwd_unit (
        .id_ex_rs1        (id_ex_rs1),
        .id_ex_rs2        (id_ex_rs2),
        .ex_mem_rd        (ex_mem_rd),
        .ex_mem_reg_write (ex_mem_reg_write),
        .mem_wb_rd        (mem_wb_rd),
        .mem_wb_reg_write (mem_wb_reg_write),
        .forward_a        (forward_a),
        .forward_b        (forward_b)
    );

    // ========================================================================
    // 4. Execution (EX) Stage & Pipeline Register
    // ========================================================================
    ex_stage ex_inst (
        .pc            (id_ex_pc),
        .pc_plus_4     (id_ex_pc_plus_4),
        .rdata1        (id_ex_rdata1),
        .rdata2        (id_ex_rdata2),
        .imm           (id_ex_imm),
        .alu_ctrl      (id_ex_alu_ctrl),
        .alua_sel      (id_ex_alua_sel),
        .alub_sel      (id_ex_alub_sel),
        .branch        (id_ex_branch),
        .jal           (id_ex_jal),
        .jalr          (id_ex_jalr),
        .funct3        (id_ex_funct3),
        .forward_a     (forward_a),
        .forward_b     (forward_b),
        .fwd_data_ex   (ex_mem_alu_result),
        .fwd_data_mem  (wb_data),
        .alu_result    (ex_alu_result),
        .store_data    (ex_store_data),
        .branch_taken  (branch_taken),
        .branch_target (branch_target)
    );

    ex_mem_reg ex_mem_reg_inst (
        .clk            (clk),
        .rst            (rst),
        .alu_result_in  (ex_alu_result),
        .store_data_in  (ex_store_data),
        .rd_in          (id_ex_rd),
        .pc_plus_4_in   (id_ex_pc_plus_4),
        .mem_read_in    (id_ex_mem_read),
        .mem_write_in   (id_ex_mem_write),
        .reg_write_in   (id_ex_reg_write),
        .wb_sel_in      (id_ex_wb_sel),
        .funct3_in      (id_ex_funct3),
        .halt_in        (id_ex_halt),
        .alu_result_out (ex_mem_alu_result),
        .store_data_out (ex_mem_store_data),
        .rd_out         (ex_mem_rd),
        .pc_plus_4_out  (ex_mem_pc_plus_4),
        .mem_read_out   (ex_mem_mem_read),
        .mem_write_out  (ex_mem_mem_write),
        .reg_write_out  (ex_mem_reg_write),
        .wb_sel_out     (ex_mem_wb_sel),
        .funct3_out     (ex_mem_funct3),
        .halt_out       (ex_mem_halt)
    );

    // ========================================================================
    // 5. Memory Access (MEM) Stage & Pipeline Register
    // ========================================================================
    mem_stage mem_inst (
        .alu_result   (ex_mem_alu_result),
        .store_data   (ex_mem_store_data),
        .funct3       (ex_mem_funct3),
        .mem_read     (ex_mem_mem_read),
        .mem_write    (ex_mem_mem_write),
        .dmem_addr    (dmem_addr),
        .dmem_wdata   (dmem_wdata),
        .dmem_byte_en (dmem_byte_en),
        .dmem_en      (dmem_en),
        .dmem_wen     (dmem_wen),
        .dmem_rdata   (dmem_rdata),
        .load_data    (mem_load_data)
    );

    mem_wb_reg mem_wb_reg_inst (
        .clk            (clk),
        .rst            (rst),
        .alu_result_in  (ex_mem_alu_result),
        .load_data_in   (mem_load_data),
        .rd_in          (ex_mem_rd),
        .pc_plus_4_in   (ex_mem_pc_plus_4),
        .reg_write_in   (ex_mem_reg_write),
        .wb_sel_in      (ex_mem_wb_sel),
        .halt_in        (ex_mem_halt),
        .alu_result_out (mem_wb_alu_result),
        .load_data_out  (mem_wb_load_data),
        .rd_out         (mem_wb_rd),
        .pc_plus_4_out  (mem_wb_pc_plus_4),
        .reg_write_out  (mem_wb_reg_write),
        .wb_sel_out     (mem_wb_wb_sel),
        .halt_out       (mem_wb_halt)
    );

    // ========================================================================
    // 6. Writeback (WB) Stage
    // ========================================================================
    wb_stage wb_inst (
        .alu_result (mem_wb_alu_result),
        .load_data  (mem_wb_load_data),
        .pc_plus_4  (mem_wb_pc_plus_4),
        .wb_sel     (mem_wb_wb_sel),
        .wb_data    (wb_data)
    );

    // Halt signal when WFI reaches WB stage
    assign halted = mem_wb_halt;

    // Performance Counters
    always @(posedge clk) begin
        if (rst) begin
            cycle_count        <= 32'd0;
            retired_inst_count <= 32'd0;
        end else if (!halted) begin
            cycle_count <= cycle_count + 32'd1;
            // Increment retired instruction count if instruction committed in WB stage
            if (mem_wb_reg_write || mem_wb_halt || (mem_wb_rd == 5'd0)) begin
                retired_inst_count <= retired_inst_count + 32'd1;
            end
        end
    end

endmodule
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

    // ========================================================================
    // 2. Shared 64 KB Unified RAM (Dual-Port)
    //    Port A: AXI4-Lite (Python Read/Write, 32-bit words)
    //    Port B: RV64 Core (Fetch 32-bit inst, Load/Store 64-bit doublewords)
    // ========================================================================
    localparam MEM_DEPTH = 8192; // 8192 * 64 bits = 64 KB
    (* ram_style = "block" *)
    reg [63:0] ram [0:MEM_DEPTH-1];

    // --- Port A: AXI Bus Access (32-bit) ---
    wire        axi_mem_we = axi_write_en && (!axi_awaddr[16]);
    wire [12:0] axi_mem_idx = axi_awaddr[15:3];
    wire [12:0] axi_rd_idx  = axi_araddr[15:3];

    // Synchronous Write from AXI
    always @(posedge s_axi_aclk) begin
        if (axi_mem_we) begin
            if (axi_awaddr[2]) begin
                // Upper 32-bit word
                if (s_axi_wstrb[0]) ram[axi_mem_idx][39:32] <= s_axi_wdata[7:0];
                if (s_axi_wstrb[1]) ram[axi_mem_idx][47:40] <= s_axi_wdata[15:8];
                if (s_axi_wstrb[2]) ram[axi_mem_idx][55:48] <= s_axi_wdata[23:16];
                if (s_axi_wstrb[3]) ram[axi_mem_idx][63:56] <= s_axi_wdata[31:24];
            end else begin
                // Lower 32-bit word
                if (s_axi_wstrb[0]) ram[axi_mem_idx][7:0]   <= s_axi_wdata[7:0];
                if (s_axi_wstrb[1]) ram[axi_mem_idx][15:8]  <= s_axi_wdata[15:8];
                if (s_axi_wstrb[2]) ram[axi_mem_idx][23:16] <= s_axi_wdata[23:16];
                if (s_axi_wstrb[3]) ram[axi_mem_idx][31:24] <= s_axi_wdata[31:24];
            end
        end
    end

    // Combinational Read to AXI
    wire [63:0] axi_line = ram[axi_rd_idx];
    wire [31:0] axi_mem_rdata_word = axi_araddr[2] ? axi_line[63:32] : axi_line[31:0];

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

    // Core Data Memory (Synchronous byte-masked write, combinational read)
    wire [12:0] core_d_idx = core_dmem_addr[15:3];

    always @(posedge s_axi_aclk) begin
        if (core_dmem_en && core_dmem_wen && !reg_reset_core) begin
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
