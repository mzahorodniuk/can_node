#-------------------------------------------------------------------------------
# build.tcl  --  headless synth -> implementation -> bitstream for can_node.
#
# Builds the bitstream with no GUI. If the project doesn't exist yet it is
# generated first from create_project.tcl, so this works on a fresh clone.
#
#     vivado -mode batch -source vivado/build.tcl
#
# Optional -tclargs flags (any order):
#     --jobs N       parallel jobs for synth/impl   (default: 4)
#     --no-bitstream stop after implementation (skip write_bitstream)
#     --reset        delete and regenerate the project before building
#
# Output bitstream is copied to  build/can_node.bit  at the repo root.
#-------------------------------------------------------------------------------

set proj_name  "can_node"
set top_module "can_node_top"

# ── Paths (relative to THIS script) ─────────────────────────────────────────
set script_dir [file normalize [file dirname [info script]]]   ;# .../vivado
set root_dir   [file normalize "$script_dir/.."]               ;# repo root
set proj_dir   "$script_dir/$proj_name"
set xpr        "$proj_dir/$proj_name.xpr"

# ── Parse -tclargs ──────────────────────────────────────────────────────────
set jobs          4
set write_bit     1
set force_reset   0
for {set i 0} {$i < [llength $argv]} {incr i} {
    switch -exact -- [lindex $argv $i] {
        "--jobs"         { incr i; set jobs [lindex $argv $i] }
        "--no-bitstream" { set write_bit 0 }
        "--reset"        { set force_reset 1 }
        default          { puts "WARNING: unknown arg '[lindex $argv $i]'" }
    }
}

# ── Make sure the project exists ────────────────────────────────────────────
if {$force_reset && [file exists $proj_dir]} {
    puts "INFO: --reset given, removing $proj_dir"
    file delete -force $proj_dir
}
if {![file exists $xpr]} {
    puts "INFO: project not found, generating it from create_project.tcl"
    source "$script_dir/create_project.tcl"
} else {
    open_project $xpr
}

# Make sure the top is set (no-op if already correct).
set_property top $top_module [get_filesets sources_1]
update_compile_order -fileset sources_1

# ── Synthesis ───────────────────────────────────────────────────────────────
puts "INFO: launching synthesis ($jobs jobs)"
reset_run synth_1
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "ERROR: synthesis failed, see synth_1 logs."
}

# ── Implementation ──────────────────────────────────────────────────────────
puts "INFO: launching implementation ($jobs jobs)"
launch_runs impl_1 -jobs $jobs
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "ERROR: implementation failed, see impl_1 logs."
}

# ── Timing summary ──────────────────────────────────────────────────────────
open_run impl_1
set wns [get_property STATS.WNS [get_runs impl_1]]
puts "INFO: post-route WNS = $wns ns"
if {$wns != "" && $wns < 0} {
    puts "WARNING: timing NOT met (negative WNS). Bitstream may be unreliable."
}

# ── Bitstream ───────────────────────────────────────────────────────────────
if {$write_bit} {
    puts "INFO: writing bitstream"
    launch_runs impl_1 -to_step write_bitstream -jobs $jobs
    wait_on_run impl_1

    set bit [glob -nocomplain "$proj_dir/$proj_name.runs/impl_1/*.bit"]
    if {[llength $bit] > 0} {
        set out_dir "$root_dir/build"
        file mkdir $out_dir
        file copy -force [lindex $bit 0] "$out_dir/$proj_name.bit"
        puts "============================================================"
        puts " Bitstream ready: $out_dir/$proj_name.bit"
        puts "============================================================"
    } else {
        error "ERROR: write_bitstream finished but no .bit found."
    }
} else {
    puts "INFO: --no-bitstream set, stopping after implementation."
}
