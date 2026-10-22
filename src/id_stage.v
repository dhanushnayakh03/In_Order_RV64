// ============================================================================
// File: id_stage.v
// Description: Instruction Decode (ID) stage and immediate generator
// Standard Verilog-2001
// ============================================================================

`include "rv64_defs.v"

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
