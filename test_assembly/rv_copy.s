/* The High-Level Goal
The program creates two arrays of 16 numbers in memory:

Array a starts at address 0x1000 (decimal 4096).
Array b starts at address 0x1100 (decimal 4352, exactly 256 bytes after a).
It calculates multiples of 10 (0, 10, 20, 30 ... 150), fills Array a with them, and then copies every single number over to Array b.

At the end of execution:

a = [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130, 140, 150]
b = [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130, 140, 150] */


.section .data
.align 3
data:
    .zero  127             # 16 elements × 8 bytes
    .dword 89

.section .text
.globl _start

_start:
    li      x6, 0            # i = 0
    li      x2, 0x1000       # source base address
    li      x31, 10          # constant 10

loop:
    slli    x3, x6, 3        # x3 = i * 8
    add     x3, x3, x6       # x3 = 9*i
    add     x3, x3, x6       # x3 = 10*i
    sd      x3, 0(x2)        # a[i] = i*10

    ld      x4, 0(x2)        # x4 = a[i]
    sd      x4, 0x100(x2)    # b[i] = a[i]

    addi    x2, x2, 8        # next 64-bit element
    addi    x6, x6, 1        # i++
    slti    x5, x6, 16       # i < 16?
    bne     x5, x0, loop

done:
    wfi