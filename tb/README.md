# Waveform testbenches

```
make -C tb                    # run all four -> tb/waves/*.vcd
make -C tb hazard             # one of: bram forwarding hazard multiplier
make -C tb view-hazard        # GTKWave with the saved trace layout (tb/gtkw/)
```

All values below are hex unless noted. A "cycle T–T+10" is the clock period
between two rising edges (rising edges at 5, 15, 25, ... ns).

---------------------------------------------------------------------------
## 1. tb_bram — BRAM memories (dmem.v, imem.v)

Inputs change 1 ns after a rising edge; the memory samples them on the next
rising edge. `phase` (ASCII) names the step.

| Cycle (ns) | phase | Inputs | Expected |
|---|---|---|---|
| 5–15, 15–25 | HOST_WR | `h_en`=1, `h_wstrb`=1111, `h_addr` 10 then 14, `h_wdata` 44332211 then 88776655 | `dmem_word_0x10` = 0000000044332211 at 15 ns, 8877665544332211 at 25 ns |
| 25–35 | RD_LATENCY | `d_en`=1, `d_we`=0, `d_addr`=10 (one cycle only) | `d_rdata` is X until **35 ns**, then 8877665544332211: data arrives one cycle after the address. Stays there while `d_en`=0 |
| 55–65 | SB_0x12 | `d_we`=00000100, `d_wdata`=AA…AA | at 65 ns `dmem_word_0x10` = 8877665544**AA**2211 (only byte 2) |
| 65–75 | SH_0x14 | `d_we`=00110000, `d_wdata`=BB…BB | at 75 ns `dmem_word_0x10` = 8877**BBBB**44AA2211 (bytes 4–5) |
| 75–85 | SD_0x18 | `d_we`=11111111 | at 85 ns `dmem_word_0x18` = DEADBEEFCAFEF00D |
| 85–95 | SW_0x1C | `d_we`=11110000, `d_wdata`=1234567812345678 | at 95 ns `dmem_word_0x18` = **12345678**CAFEF00D (upper word only) |
| 95–105 | READ_FIRST | write 0123456789ABCDEF to 18 **and** read 18 | at 105 ns: `dmem_word_0x18` = 0123456789ABCDEF (new) but `d_rdata` = 12345678CAFEF00D (old): read-first |
| 105–115 | READ_AFTER | read 18 | at 115 ns `d_rdata` = 0123456789ABCDEF |
| 115–145 | PIPELINED | `d_addr` 10, 18, 10 (one per cycle) | `d_rdata` at 125: 8877BBBB44AA2211, 135: 0123456789ABCDEF, 145: 8877BBBB44AA2211. One read per cycle, each one cycle late |
| 145–165 | HOLD_EN0 | `d_en`=0, `d_addr`=18 | `d_rdata` stays 8877BBBB44AA2211 (does not change to the value at 18) |
| 165–185 | HOST_RD | `h_en`=1, `h_wstrb`=0000, `h_addr` 14 then 10 | `h_rdata` = 8877BBBB at 175 ns, 44AA2211 at 185 ns |
| 195–235 | I_HOST_WR | `ih_we`=1, `ih_addr` 0,4,8,C | program written into IMEM |
| 235–255 | I_FETCH | `i_en`=1, `i_addr` 0 then 4 | `i_rdata` = 00A00093 at 245, 01400113 at 255 |
| 255–275 | I_STALL | `i_en`=0, `i_addr`=8 | `i_rdata` **holds** 01400113 for both cycles |
| 275–295 | I_FETCH | `i_en`=1, `i_addr` 8 then C | `i_rdata` = 002081B3 at 285, 10500073 at 295 |

Also visible: in every write cycle `d_rdata` returns the *old* contents of
that dword (e.g. 0 at 85 ns, DEADBEEFCAFEF00D at 95 ns).

---------------------------------------------------------------------------
## 2. tb_forwarding — forwarding_unit.v

Combinational. Case k is applied from 10k to 10k+10 ns. Codes: 00 NONE,
10 EX/MEM1, 11 MEM1/MEM2, 01 MEM2/WB (also as text in `fwd_a_src`/`fwd_b_src`).
`ok` must be 1 throughout.

| case_id | rs1 rs2 | EX/MEM1 rd,we | MEM1/MEM2 rd,we | MEM2/WB rd,we | forward_a | forward_b | Shows |
|---|---|---|---|---|---|---|---|
| 1 | 5 6 | 7,1 | 8,1 | 9,1 | 00 NONE | 00 NONE | no match |
| 2 | 5 6 | 5,1 | 8,1 | 9,1 | 10 MEM1 | 00 | distance 1 |
| 3 | 5 6 | 7,1 | 5,1 | 9,1 | 11 MEM2 | 00 | distance 2 |
| 4 | 5 6 | 7,1 | 8,1 | 5,1 | 01 WB | 00 | distance 3 |
| 5 | 5 6 | 7,1 | 8,1 | 6,1 | 00 | 01 WB | rs2 path |
| 6 | 5 6 | 5,1 | 8,1 | 6,1 | 10 MEM1 | 01 WB | both operands, different stages |
| 7 | 5 6 | 5,1 | 5,1 | 5,1 | 10 MEM1 | 00 | youngest wins |
| 8 | 5 6 | 7,1 | 5,1 | 5,1 | 11 MEM2 | 00 | youngest wins |
| 9 | 5 6 | 5,**0** | 8,1 | 5,1 | 01 WB | 00 | no RegWrite → skipped |
| 10 | 0 0 | 0,1 | 0,1 | 0,1 | 00 | 00 | x0 never forwarded |
| 11 | 5 5 | 5,1 | 8,1 | 9,1 | 10 MEM1 | 10 MEM1 | same reg on both |
| 12 | 31 31 | 7,1 | 31,1 | 9,1 | 11 MEM2 | 11 MEM2 | x31 |

---------------------------------------------------------------------------
## 3. tb_hazard — hazard_detection.v

Combinational. Case k applied from 10k to 10k+10 ns. `scenario` is the label.
`ctrl` = {stall_pc, stall_if2, stall_if_id, stall_id_ex, flush_if2,
flush_if_id, flush_id_ex, flush_ex_mem}. `ok` must be 1 throughout.

| case_id | scenario | Key inputs | ctrl | Meaning |
|---|---|---|---|---|
| 1 | IDLE | nothing | 0000_0000 | |
| 2 | LU_EX_RS1 | load x5 in EX, ID uses rs1=x5 | 1110_0010 | freeze PC/IF2/ID, bubble into EX |
| 3 | LU_MEM1_RS1 | same load now in MEM1 | 1110_0010 | 2nd stall cycle |
| 4 | LU_RELEASED | load gone past MEM1 | 0000_0000 | consumer proceeds (2 cycles total, cases 2–4) |
| 5 | LU_EX_RS2 | ID uses rs2=x5 (ALU) | 1110_0010 | |
| 6 | LU_STORE_DATA | ID is store, rs2=x5 is store data | 0000_0000 | no stall: late store-data forward |
| 7 | LU_STORE_ADDR | ID is store, rs1=x5 is address | 1110_0010 | address needed in EX → stall |
| 8 | LU_RD_X0 | load writes x0 | 0000_0000 | |
| 9 | LU_NOT_USED | uses_rs1=uses_rs2=0 (e.g. lui) | 0000_0000 | |
| 10 | ALU_IN_EX | x5 producer in EX is not a load | 0000_0000 | forwarding handles it |
| 11 | BRANCH_TAKEN | branch_taken=1 | 0000_1110 | flush IF2, ID, EX-entry |
| 12 | MULT_BUSY | mult_busy=1 | 1111_0001 | freeze up to EX, bubble into MEM1 |
| 13 | STOP_FETCH | stop_fetch=1 | 1000_1100 | freeze PC, flush IF2 and ID |
| 14 | PRIO_BR_OVER_LU | branch + load-use | 0000_1110 | branch wins |
| 15 | PRIO_MUL_OVER_LU | mult + load-use | 1111_0001 | multiplier wins |
| 16 | PRIO_STOP_OVR_LU | stop_fetch + load-use | 1000_1100 | stop_fetch wins |
| 17 | PRIO_BR_OVER_ALL | branch + mult + stop + load-use | 0000_1110 | branch wins |

---------------------------------------------------------------------------
## 4. tb_multiplier — 4-cycle multiplier in ex_stage.v

Instruction i is in EX from 15+40i to 55+40i ns (4 cycles). Inside it:
`mult_cnt` = 0,1,2,3; `mult_busy` = 1,1,1,0; `hold_opa`/`hold_opb` load at the
first edge (25+40i). `exmem1_result` changes at 55+40i, the edge where
`mult_busy` is 0. `ok` must be 1 throughout (`exmem1_result` = `exmem1_exp`).

| i | op_name | operand_a × operand_b | In EX (ns) | exmem1_result at |
|---|---|---|---|---|
| 0 | mul | 7 × 6 | 15–55 | 000000000000002A @55 |
| 1 | mul | −1 × −1 | 55–95 | 0000000000000001 @95 |
| 2 | mulh | −1 × −1 | 95–135 | 0000000000000000 @135 |
| 3 | mulhu | FFFF…FF × FFFF…FF | 135–175 | FFFFFFFFFFFFFFFE @175 |
| 4 | mulhsu | −1 × FFFF…FF (unsigned) | 175–215 | FFFFFFFFFFFFFFFF @215 |
| 5 | mulh | 8000…00 × 8000…00 | 215–255 | 4000000000000000 @255 |
| 6 | mulh | 8000…00 × −1 | 255–295 | 0000000000000000 @295 |
| 7 | mulw | 7FFFFFFF × 2 | 295–335 | FFFFFFFFFFFFFFFE @335 (sign-extended) |
| 8 | mulw | DEADBEEF_00000003 × 12345678_00000005 | 335–375 | 000000000000000F @375 (upper halves ignored) |
| 9 | mulfwd | 1234 (forwarded) × 10 | 375–415 | 0000000000012340 @415 |
| 10 | add | 3 + 4 | 415–425 | 0000000000000007 @425 |

Op 9 (hold registers): `forward_a`=10 (from EX/MEM1). `fwd_data_mem1` and
`operand_a` are 1234 only in 375–385, then 0BAD0BAD0BAD0BAD. `hold_opa`
becomes 1234 at 385 and `alu_result` stays 12340 for the whole op.
Op 10: `mult_cnt` stays 0 and `mult_busy` stays 0: single cycle.

Note: in simulation `alu_result` already shows the product in the first
cycle because the multiplier logic has zero delay here; what the 4 cycles
control is *when* the result is captured (`exmem1_result`).
