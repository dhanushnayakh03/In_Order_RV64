.section .text.init
.globl _start

# ============================================================================
# File: ld_sd_forw.s
# Description: Simple test for MEM-to-MEM (Load-to-Store) Forwarding
#
# Logic:
# 1. Store 42 into mem[0x1000]
# 2. Back-to-back:
#      ld x3, 0(x1)     <- loads 42 into x3
#      sd x3, 8(x1)     <- immediately stores x3 into mem[0x1008]!
#    With MEM-to-MEM forwarding, this executes with 0 STALLS!
# 3. Store 99 into mem[0x1010]
# 4. Back-to-back:
#      ld x5, 16(x1)    <- loads 99 into x5
#      sd x5, 24(x1)    <- immediately stores x5 into mem[0x1018]!
# 5. Read back into x6 and x7 to verify.
# ============================================================================

_start:
    # 1. Base pointer
    li   x1, 0x1000

    # 2. Store initial value 42 into mem[0x1000]
    li   x2, 42
    sd   x2, 0(x1)         # mem[0x1000] = 42

    # 3. Test 1: MEM-to-MEM Forwarding (ld immediately followed by sd of x3)
    ld   x3, 0(x1)         # Load 42 into x3
    sd   x3, 8(x1)         # Store x3 into mem[0x1008] (0 stalls via MEM-to-MEM forwarding!)

    # 4. Store initial value 99 into mem[0x1010]
    li   x4, 99
    sd   x4, 16(x1)        # mem[0x1010] = 99

    # 5. Test 2: Second back-to-back ld -> sd
    ld   x5, 16(x1)        # Load 99 into x5
    sd   x5, 24(x1)        # Store x5 into mem[0x1018] (0 stalls via MEM-to-MEM forwarding!)

    # 6. Read back to verify in registers
    ld   x6, 8(x1)         # x6 should be 42
    ld   x7, 24(x1)        # x7 should be 99

    add x6 , x7 , x6 
    sd  x6 , 32(x1)        # mem[0x1020] = 141  should happen with 0 stalls 

    sd x1 , 40(x1) 
    ld x1 , 40(x1) 
    sd x6 , 48(x1)  # should stall for one cycle 

    # 7. Halt
    wfi

    #total instructions = 17
    #total cycles = 16 + 5 + 1 = 22
