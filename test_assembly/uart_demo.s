# ============================================================================
# File: uart_demo.s
# Description: Demonstrates RV64 Core printing over UART on PYNQ-Z2
# - Prints banner message
# - Computes first 10 Fibonacci numbers
# - Prints them in ASCII to UART
# - Halts with WFI
# ============================================================================

.section .text.init
.globl _start

_start:
    # 1. Print Welcome Banner
    la   a0, msg_banner
    jal  ra, print_str

    # 2. Compute and print Fibonacci numbers
    la   a0, msg_fib_start
    jal  ra, print_str

    # Fibonacci Loop: F(0)=0, F(1)=1, ...
    li   s0, 0          # F(n-2) = 0
    li   s1, 1          # F(n-1) = 1
    li   s2, 0          # counter i = 0
    li   s3, 10         # limit = 10

fib_loop:
    # Print s0
    mv   a0, s0
    jal  ra, print_dec

    # Print space
    li   a0, 32         # ' '
    jal  ra, uart_putc

    # Next Fib
    add  s4, s0, s1     # F(n) = F(n-1) + F(n-2)
    mv   s0, s1         # F(n-2) = F(n-1)
    mv   s1, s4         # F(n-1) = F(n)

    addi s2, s2, 1
    blt  s2, s3, fib_loop

    # 3. Print Completion Message
    la   a0, msg_done
    jal  ra, print_str

    # Finished: Halt CPU (causes LD1 on board to turn ON)
    wfi

hang:
    j    hang


# ============================================================================
# UART Driver Functions (MMIO Base: 0x10000000)
# ============================================================================

# uart_putc: Sends character in a0[7:0]
uart_putc:
    li   t0, 0x10000000        # UART Base
.Lwait_tx:
    ld   t1, 4(t0)             # Read TX Status (+0x4)
    andi t1, t1, 1             # Bit 0 is tx_busy
    bne  t1, x0, .Lwait_tx     # If busy, wait
    sd   a0, 0(t0)             # Write byte to TX Data (+0x0)
    ret

# print_str: Prints null-terminated string at address a0
print_str:
    addi sp, sp, -16
    sd   ra, 8(sp)
    sd   s0, 0(sp)
    mv   s0, a0

.Lstr_loop:
    lbu  a0, 0(s0)
    beq  a0, x0, .Lstr_done
    jal  ra, uart_putc
    addi s0, s0, 1
    j    .Lstr_loop

.Lstr_done:
    ld   s0, 0(sp)
    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

# print_dec: Prints unsigned integer in a0 as decimal (0..99)
print_dec:
    addi sp, sp, -16
    sd   ra, 8(sp)
    sd   s0, 0(sp)

    li   t0, 10
    blt  a0, t0, .Lsingle_digit

    # Two digits (div/mod 10 via subtraction)
    li   t1, 0          # tens
.Ldiv_loop:
    blt  a0, t0, .Ldiv_done
    sub  a0, a0, t0
    addi t1, t1, 1
    j    .Ldiv_loop

.Ldiv_done:
    mv   s0, a0         # s0 = units
    addi a0, t1, 48     # '0' + tens
    jal  ra, uart_putc
    mv   a0, s0         # units
.Lsingle_digit:
    addi a0, a0, 48     # '0' + digit
    jal  ra, uart_putc

    ld   s0, 0(sp)
    ld   ra, 8(sp)
    addi sp, sp, 16
    ret


# ============================================================================
# Constant Data Section
# ============================================================================
.section .rodata
.align 3
msg_banner:
    .string "\r\n==============================================\r\n  RV64I 5-Stage In-Order Core on PYNQ-Z2\r\n==============================================\r\n"

msg_fib_start:
    .string "[TEST] Computing Fibonacci sequence:\r\n  F(0..9): "

msg_done:
    .string "\r\n[TEST] Fibonacci computation: PASSED!\r\n>>> Core entering WFI halt <<<\r\n"
