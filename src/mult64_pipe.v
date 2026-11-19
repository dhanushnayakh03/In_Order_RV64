// ============================================================================
// File: mult64_pipe.v
// Description: Staged 64 x 64 multiplier for RV64M (MUL, MULH, MULHSU, MULHU,
//              MULW). Shared, identical copy in both cores:
//                OOO_processor/src/mult64_pipe.v
//                In_Order_RV64/src/mult64_pipe.v
//
// Datapath (one stage of real hardware per cycle, registered in between):
//
//   cycle 0  start    : operands presented              -> S1 regs (a, b, flags)
//   cycle 1  stage E2 : 16 multipliers, 16 x 16 bit     -> S2 regs (16 partial products)
//                       (each maps to one DSP48 slice)     + sign correction term
//   cycle 2  stage E3 : 4 row adders                     -> S3 regs (4 x 80-bit rows)
//                       row_i = a_i * b  (a_i = 16-bit digit i of a)
//   cycle 3  stage E4 : final adder tree, sign fix-up,  -> result_comb, captured by the
//                       op select                           core's own register
//                                                           (OoO: fu_c, in-order: EX/MEM)
//
// Signed operands: the array always forms the UNSIGNED product Ua*Ub. For a
// 65-bit signed view A = Ua - 2^64*an, B = Ub - 2^64*bn (an/bn = operand is
// signed and negative):
//     A*B mod 2^128 = Ua*Ub - 2^64 * (an*Ub + bn*Ua)
// so only the upper 64 bits need the correction  hi -= (an ? Ub : 0) + (bn ? Ua : 0).
// The low 64 bits are the same for every signedness (MUL, MULW use them).
//
// Occupancy: ONE multiply at a time. 'busy' is high while S1..S3 hold an
// operation; the core must not start a new multiply while busy. 'done' is
// high in the cycle result_comb is valid (cycle 3).
// Standard Verilog-2001 (no includes, so both cores can use the same file)
// ============================================================================

module mult64_pipe (
    input  wire         clk,
    input  wire         rst,
    input  wire         flush,      // drop the operation in flight (OoO recovery)

    // Start (cycle 0)
    input  wire         start,
    input  wire [63:0]  a,
    input  wire [63:0]  b,
    input  wire         a_signed,   // MUL, MULH, MULHSU
    input  wire         b_signed,   // MUL, MULH
    input  wire         sel_hi,     // MULH, MULHSU, MULHU: upper 64 bits
    input  wire         is_word,    // MULW: sign-extended low 32 bits

    // Status / result
    output wire         busy,       // an operation is in S1..S3
    output wire         done,       // result_comb valid this cycle
    output wire [63:0]  result_comb
);

    // ------------------------------------------------------------------------
    // S1: operands and control
    // ------------------------------------------------------------------------
    reg         s1_v;
    reg [63:0]  s1_a, s1_b;
    reg         s1_an, s1_bn, s1_hi, s1_w;

    always @(posedge clk) begin
        if (rst || flush) begin
            s1_v <= 1'b0;
        end else begin
            s1_v <= start;
        end
        if (start) begin
            s1_a  <= a;
            s1_b  <= b;
            s1_an <= a_signed & a[63];
            s1_bn <= b_signed & b[63];
            s1_hi <= sel_hi;
            s1_w  <= is_word;
        end
    end

    // ------------------------------------------------------------------------
    // E2: 16 partial products a_i * b_j (16 x 16 -> 32 bits)  -> S2
    //     pp[4*i + j] has weight 2^(16*(i+j))
    // ------------------------------------------------------------------------
    reg         s2_v;
    reg [31:0]  s2_pp [0:15];
    reg [63:0]  s2_corr;
    reg         s2_hi, s2_w;

    integer i, j;
    always @(posedge clk) begin
        if (rst || flush) begin
            s2_v <= 1'b0;
        end else begin
            s2_v <= s1_v;
        end
        if (s1_v) begin
            for (i = 0; i < 4; i = i + 1)
                for (j = 0; j < 4; j = j + 1)
                    s2_pp[4*i + j] <= s1_a[16*i +: 16] * s1_b[16*j +: 16];
            s2_corr <= (s1_an ? s1_b : 64'd0) + (s1_bn ? s1_a : 64'd0);
            s2_hi   <= s1_hi;
            s2_w    <= s1_w;
        end
    end

    // ------------------------------------------------------------------------
    // E3: row sums  row_i = sum_j pp[i][j] << 16j  (= a_i * b, 80 bits) -> S3
    //     pp[i][0], pp[i][2] do not overlap (weights 0, 32) -> concatenate;
    //     same for pp[i][1], pp[i][3] (weights 16, 48). One 2-input add per row.
    // ------------------------------------------------------------------------
    reg         s3_v;
    reg [79:0]  s3_row [0:3];
    reg [63:0]  s3_corr;
    reg         s3_hi, s3_w;

    integer r;
    always @(posedge clk) begin
        if (rst || flush) begin
            s3_v <= 1'b0;
        end else begin
            s3_v <= s2_v;
        end
        if (s2_v) begin
            for (r = 0; r < 4; r = r + 1)
                s3_row[r] <= {16'd0, s2_pp[4*r + 2], s2_pp[4*r + 0]}
                           + {s2_pp[4*r + 3], s2_pp[4*r + 1], 16'd0};
            s3_corr <= s2_corr;
            s3_hi   <= s2_hi;
            s3_w    <= s2_w;
        end
    end

    // ------------------------------------------------------------------------
    // E4: product = row0 + row1<<16 + row2<<32 + row3<<48, sign fix-up, select
    // ------------------------------------------------------------------------
    wire [127:0] prod = {48'd0, s3_row[0]}
                      + {32'd0, s3_row[1], 16'd0}
                      + {16'd0, s3_row[2], 32'd0}
                      + {s3_row[3], 48'd0};

    wire [63:0]  prod_lo = prod[63:0];
    wire [63:0]  prod_hi = prod[127:64] - s3_corr;

    assign result_comb = s3_w  ? {{32{prod_lo[31]}}, prod_lo[31:0]} :
                         s3_hi ? prod_hi : prod_lo;

    assign busy = s1_v | s2_v | s3_v;
    assign done = s3_v;

endmodule
