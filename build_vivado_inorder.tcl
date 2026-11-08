# ==============================================================================
# File: build_vivado_inorder.tcl
# Description: Vivado project + block design setup for the 7-stage in-order
#              RV64 core (BRAM IMEM/DMEM) on PYNQ-Z2. After it finishes, click
#              "Generate Bitstream" in the Flow Navigator.
# Target Board: PYNQ-Z2 (Zynq-7000 xc7z020clg400-1)
# Top Module:   design_1_wrapper (Zynq PS + rv64_pynq_top_0)
#
# Usage (from the In_Order_RV64 directory, which must contain src/):
#   Vivado GUI : Tools -> Run Tcl Script... -> build_vivado_inorder.tcl
#   Tcl console: source build_vivado_inorder.tcl
#
# Outputs after "Generate Bitstream" (copy both to the board, same basename):
#   <project>/<name>.runs/impl_1/design_1_wrapper.bit            -> rv64_core.bit
#   <project>/<name>.gen/sources_1/bd/design_1/hw_handoff/design_1.hwh -> rv64_core.hwh
#     (Vivado < 2020.2: <project>/<name>.srcs/sources_1/bd/design_1/hw_handoff/)
# ==============================================================================

# ---------------------------------------------------------------------------
# User settings
# ---------------------------------------------------------------------------
# Core clock (FCLK0). The core runs directly on the AXI clock. The combinational
# 64x64 multiplier is the likely critical path: start here, check WNS in the
# timing summary, and raise/lower and rebuild as needed.
set core_clk_mhz 20

# AXI window of the IP: memory 0x00000-0x0FFFF, registers 0x10000-0x101FF
# (C_S_AXI_ADDR_WIDTH = 18). Must be >= 128K.
set ip_addr_range 256K

# ---------------------------------------------------------------------------
# Paths / project
# ---------------------------------------------------------------------------
set script_dir [file dirname [file normalize [info script]]]
if {$script_dir eq ""} { set script_dir "." }
set src_dir [file join $script_dir "src"]

set project_name "pynq_rv64_inorder"
set project_dir  [file join $script_dir "vivado_project_inorder"]
set part_number  "xc7z020clg400-1"

puts "=================================================================="
puts " Creating Clean Vivado Project: $project_name for $part_number"
puts " Project Location: $project_dir"
puts " Core clock (FCLK0): $core_clk_mhz MHz"
puts "=================================================================="

# 1. Close any open project and create a fresh one
catch { close_project }
catch { file delete -force $project_dir }
create_project -force $project_name $project_dir -part $part_number

# Use the PYNQ-Z2 board file if it is installed (optional)
set pynq_boards [get_board_parts -quiet -latest_file_version "*pynq-z2*"]
if {[llength $pynq_boards] > 0} {
    set_property board_part [lindex $pynq_boards 0] [current_project]
    puts " Board part: [lindex $pynq_boards 0]"
} else {
    puts " PYNQ-Z2 board files not installed: continuing with part only."
}

# 2. Add RTL sources (Verilog-2001)
set src_files [list \
    [file join $src_dir "rv64_defs.v"] \
    [file join $src_dir "regfile.v"] \
    [file join $src_dir "alu.v"] \
    [file join $src_dir "branch_cond.v"] \
    [file join $src_dir "forwarding_unit.v"] \
    [file join $src_dir "hazard_detection.v"] \
    [file join $src_dir "if_stage.v"] \
    [file join $src_dir "id_stage.v"] \
    [file join $src_dir "ex_stage.v"] \
    [file join $src_dir "mem_stage.v"] \
    [file join $src_dir "pipeline_registers.v"] \
    [file join $src_dir "core_top.v"] \
    [file join $src_dir "imem.v"] \
    [file join $src_dir "dmem.v"] \
    [file join $src_dir "rv64_pynq_top.v"] \
]

foreach f $src_files {
    if {![file exists $f]} {
        error "Missing source file: $f (run this script from the In_Order_RV64 directory)"
    }
}

add_files -norecurse $src_files
# rv64_defs.v holds only `defines (include-guarded): treat it as a header
set_property file_type {Verilog Header} [get_files rv64_defs.v]
set_property include_dirs $src_dir [get_filesets sources_1]
update_compile_order -fileset sources_1

# 3. Create Block Design
puts "=================================================================="
puts " Building Block Design with ZYNQ PS & rv64_pynq_top_0"
puts "=================================================================="
create_bd_design "design_1"

# Zynq Processing System
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7_0

# Board preset (DDR / MIO for PYNQ-Z2) if board files exist; external DDR/FIXED_IO
catch {
    apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable" } [get_bd_cells ps7_0]
}
catch {
    make_bd_intf_pins_external [get_bd_intf_pins ps7_0/DDR]
    make_bd_intf_pins_external [get_bd_intf_pins ps7_0/FIXED_IO]
}

# Enable M_AXI_GP0, FCLK0 and its reset (set after the preset so it is not overridden)
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_EN_CLK0_PORT {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ $core_clk_mhz \
    CONFIG.PCW_EN_RST0_PORT {1} \
] [get_bd_cells ps7_0]

# In-order core AXI wrapper as a module reference
create_bd_cell -type module -reference rv64_pynq_top rv64_pynq_top_0

# Slave AXI interface (inferred from the s_axi_* port names)
set axi_intf [get_bd_intf_pins rv64_pynq_top_0/s_axi]
if {[llength $axi_intf] == 0} {
    set axi_intf [get_bd_intf_pins -of_objects [get_bd_cells rv64_pynq_top_0]]
}

# AXI interconnect, clock (FCLK0) and reset (proc_sys_reset) automation
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { \
    Master "/ps7_0/M_AXI_GP0" \
    Clk "Auto" \
} $axi_intf

# 4. Address map: the IP needs a 256K window (base 0x4000_0000)
assign_bd_address
set seg_done 0
foreach seg [get_bd_addr_segs -quiet -of_objects [get_bd_addr_spaces ps7_0/Data]] {
    if {[string match -nocase "*rv64_pynq_top_0*" $seg]} {
        if {[catch {
            set_property range  $ip_addr_range $seg
            set_property offset 0x40000000     $seg
        } err]} {
            puts "WARNING: could not set address range automatically: $err"
        } else {
            set seg_done 1
            puts " Address segment $seg: offset 0x40000000, range $ip_addr_range"
        }
    }
}
if {!$seg_done} {
    puts "WARNING: set the rv64_pynq_top_0 range to $ip_addr_range manually in the Address Editor."
}

# Validate and save
validate_bd_design
save_bd_design

# 5. Output products & HDL wrapper
puts "=================================================================="
puts " Generating Block Design Output Products & HDL Wrapper"
puts "=================================================================="
set bd_file [get_files "design_1.bd"]
set_property synth_checkpoint_mode Hierarchical $bd_file
generate_target all $bd_file
set wrapper_file [make_wrapper -files $bd_file -top]
add_files -norecurse $wrapper_file
set_property top design_1_wrapper [current_fileset]
update_compile_order -fileset sources_1

puts "=================================================================="
puts " PROJECT SETUP COMPLETED SUCCESSFULLY!"
puts " 1. Click 'Generate Bitstream' in the Flow Navigator (bottom left)."
puts "    (When prompted, 1 or 2 jobs keep RAM usage low.)"
puts " 2. After synthesis, check the synthesis log 'Block RAM: Final Mapping"
puts "    Report' (expect 32 x RAMB36) and Report Utilization (LUT as Memory ~0)."
puts " 3. After implementation, check WNS >= 0 in the Timing Summary. If it"
puts "    fails, lower core_clk_mhz at the top of this script and rerun it."
puts " 4. Copy to the board, renamed to the same basename:"
puts "      design_1_wrapper.bit -> rv64_core.bit"
puts "      design_1.hwh         -> rv64_core.hwh"
puts "    together with run_fpga.py and program.bin (make fpga_mem SOURCE=x.s)"
puts "=================================================================="
