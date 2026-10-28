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
