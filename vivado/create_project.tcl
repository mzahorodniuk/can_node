#-------------------------------------------------------------------------------
# create_project.tcl  --  regenerate the can_node Vivado project from sources.
#
# The .xpr and all generated output are disposable: this script is the source
# of truth. Run it from the repo root or anywhere:
#
#     vivado -mode batch -source vivado/create_project.tcl
#
# or, inside the Vivado Tcl console:
#
#     cd <repo>/vivado ; source create_project.tcl
#
# Add  -tclargs --open  to launch the GUI when done.
#-------------------------------------------------------------------------------

# ── Project settings ───────────────────────────────────────────────────────
set proj_name   "can_node"
set part        "xc7z020clg400-1"
# Set a board_part too if you have the PYNQ-Z1 board files installed:
set board_part  "www.tul.com.tw:pynq-z1:part0:1.0"
set top_module  "can_node_top"

# ── Paths (resolved relative to THIS script) ────────────────────────────────
set script_dir [file normalize [file dirname [info script]]]   ;# .../vivado
set root_dir   [file normalize "$script_dir/.."]                ;# repo root
set proj_dir   "$script_dir/$proj_name"

# ── Fresh project ───────────────────────────────────────────────────────────
create_project -force $proj_name $proj_dir -part $part

# Attach board files if available (ignored gracefully if not installed).
if {[catch {set_property board_part $board_part [current_project]} err]} {
    puts "WARNING: board_part '$board_part' not found, continuing with part only."
}

set_property target_language VHDL [current_project]

# ── Design sources (VHDL-2008) ──────────────────────────────────────────────
set src_files [glob -nocomplain "$root_dir/src/*.vhd"]
if {[llength $src_files] > 0} {
    add_files -fileset sources_1 $src_files
    set_property file_type {VHDL 2008} [get_files $src_files]
}

# ── Constraints ─────────────────────────────────────────────────────────────
set xdc_files [glob -nocomplain "$root_dir/constraints/*.xdc"]
if {[llength $xdc_files] > 0} {
    add_files -fileset constrs_1 $xdc_files
}

# ── Simulation sources ──────────────────────────────────────────────────────
set tb_files [glob -nocomplain "$root_dir/tb/*.vhd"]
if {[llength $tb_files] > 0} {
    add_files -fileset sim_1 $tb_files
    set_property file_type {VHDL 2008} [get_files $tb_files]
}

# ── Tops ────────────────────────────────────────────────────────────────────
set_property top $top_module [get_filesets sources_1]
catch { set_property top "can_node_tb" [get_filesets sim_1] }
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "============================================================"
puts " can_node project created at:"
puts "   $proj_dir/$proj_name.xpr"
puts "============================================================"

# ── Optional: open GUI when called with -tclargs --open ─────────────────────
if {[lsearch -exact $argv "--open"] >= 0} {
    start_gui
}
