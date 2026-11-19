# ==============================================================================
# build_inorder.tcl : Vivado project for the 7-stage in-order core (rv64_pynq_top) on PYNQ-Z2
#
# Lives in the In_Order_RV64 repo root and uses only ./src: clone the repo and run it.
# Afterwards copy the inorder/ folder (.bit + .hwh) into the SD-card folder
# (verification_comp/fpga/sdcard/inorder/, next to the .mem files).
#
#   Vivado GUI : Tools -> Run Tcl Script... -> build_inorder.tcl
#   Tcl console: source <path>/build_inorder.tcl
#
# Then click "Generate Bitstream". When it is done, type in the Tcl console:
#   export_bitstream
# which copies the results into ./inorder/ (next to this script):
#   inorder/inorder.bit  and  inorder/inorder.hwh
#
# master.py mode: inorder. Expected signature register (0x10018): 0xC0DE1001
# ==============================================================================

# ---- settings ----------------------------------------------------------------
set core_clk_mhz 20          ;# FCLK0 = core clock. Cycle counts do not depend on it.
                              # Check WNS >= 0 in the timing summary after implementation.

set script_dir   [file dirname [file normalize [info script]]]
set src_dir      [file join $script_dir src]
set sdcard_dir   [file join $script_dir inorder]
set project_name "pynq_inorder"
set project_dir  [file join $script_dir "vivado_inorder"]
set part_number  "xc7z020clg400-1"

puts "=================================================================="
puts " In-order core project: $project_name ($part_number), FCLK0 $core_clk_mhz MHz"
puts " RTL     : $src_dir"
puts " Project : $project_dir"
puts "=================================================================="

# ---- 1. project ----------------------------------------------------------------
catch { close_project }
catch { file delete -force $project_dir }
create_project -force $project_name $project_dir -part $part_number
set pynq_boards [get_board_parts -quiet -latest_file_version "*pynq-z2*"]
if {[llength $pynq_boards] > 0} {
    set_property board_part [lindex $pynq_boards 0] [current_project]
    puts " Board part: [lindex $pynq_boards 0]"
}

# ---- 2. RTL sources ----------------------------------------------------------------
set src_names {
    rv64_defs.v regfile.v alu.v mult64_pipe.v branch_cond.v forwarding_unit.v
    hazard_detection.v if_stage.v id_stage.v ex_stage.v mem_stage.v
    pipeline_registers.v core_top.v imem.v dmem.v rv64_pynq_top.v
}
set src_files {}
foreach n $src_names {
    set f [file join $src_dir $n]
    if {![file exists $f]} { error "Missing RTL file: $f" }
    lappend src_files $f
}
add_files -norecurse $src_files
# rv64_defs.v holds only `defines (include-guarded): treat it as a header
set_property file_type {Verilog Header} [get_files rv64_defs.v]
set_property include_dirs $src_dir [get_filesets sources_1]
update_compile_order -fileset sources_1

# ---- 3. block design: Zynq PS + rv64_pynq_top ----------------------------------------
create_bd_design "design_1"
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7_0
catch {
    apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable" } [get_bd_cells ps7_0]
}
catch {
    make_bd_intf_pins_external [get_bd_intf_pins ps7_0/DDR]
    make_bd_intf_pins_external [get_bd_intf_pins ps7_0/FIXED_IO]
}
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_EN_CLK0_PORT {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ $core_clk_mhz \
    CONFIG.PCW_EN_RST0_PORT {1} \
] [get_bd_cells ps7_0]

create_bd_cell -type module -reference rv64_pynq_top rv64_pynq_top_0
set axi_intf [get_bd_intf_pins rv64_pynq_top_0/s_axi]
if {[llength $axi_intf] == 0} {
    set axi_intf [get_bd_intf_pins -of_objects [get_bd_cells rv64_pynq_top_0]]
}
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { Master "/ps7_0/M_AXI_GP0" Clk "Auto" } $axi_intf

# the IP decodes memory 0x00000-0x0FFFF and registers 0x10000-0x101FF: give it a 256K window
catch { assign_bd_address }
set seg_done 0
foreach seg [get_bd_addr_segs -quiet -of_objects [get_bd_addr_spaces ps7_0/Data]] {
    if {[string match -nocase "*rv64_pynq_top_0*" $seg]} {
        if {![catch { set_property range 256K $seg; set_property offset 0x40000000 $seg }]} {
            set seg_done 1
            puts " Address segment $seg: offset 0x40000000, range 256K"
        }
    }
}
if {!$seg_done} { puts "WARNING: set rv64_pynq_top_0 to range 256K in the Address Editor." }
validate_bd_design
save_bd_design

# ---- 4. output products + HDL wrapper ------------------------------------------------
set bd_file [get_files "design_1.bd"]
set_property synth_checkpoint_mode Hierarchical $bd_file
generate_target all $bd_file
add_files -norecurse [make_wrapper -files $bd_file -top]
set_property top design_1_wrapper [current_fileset]
update_compile_order -fileset sources_1

# ---- 5. export_bitstream: copy .bit + .hwh to ./inorder/ ---------------------------
proc export_bitstream {} {
    global project_dir project_name sdcard_dir
    set bit [file join $project_dir "$project_name.runs/impl_1/design_1_wrapper.bit"]
    set hwh ""
    foreach d [list "$project_name.gen" "$project_name.srcs"] {
        set h [file join $project_dir "$d/sources_1/bd/design_1/hw_handoff/design_1.hwh"]
        if {[file exists $h]} { set hwh $h; break }
    }
    if {![file exists $bit]} { error "No bitstream yet: $bit (run Generate Bitstream first)" }
    if {$hwh eq ""}          { error "No design_1.hwh found under $project_dir" }
    file mkdir $sdcard_dir
    file copy -force $bit [file join $sdcard_dir "inorder.bit"]
    file copy -force $hwh [file join $sdcard_dir "inorder.hwh"]
    puts " Copied to $sdcard_dir : inorder.bit, inorder.hwh"
}

puts "=================================================================="
puts " PROJECT READY"
puts " 1. Click 'Generate Bitstream' (1-2 jobs keep RAM usage low)."
puts " 2. Check the Timing Summary: WNS >= 0 at $core_clk_mhz MHz."
puts " 3. In this Tcl console type:  export_bitstream"
puts "    -> $sdcard_dir/inorder.bit + inorder.hwh"
puts "=================================================================="
