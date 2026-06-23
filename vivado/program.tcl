#-------------------------------------------------------------------------------
# program.tcl  --  load a bitstream onto the PYNQ-Z1 over JTAG, headless.
#
# Requires the board powered on and connected by USB-JTAG, and a hw_server.
# connect_hw_server auto-launches a local hw_server if one isn't running.
#
#     vivado -mode batch -source vivado/program.tcl
#
# Optional -tclargs flags (any order):
#     --bit <path>   bitstream to load   (default: build/can_node.bit,
#                     falling back to the impl_1 run output)
#     --url <host:p> hw_server URL       (default: localhost:3121)
#     --device <id>  JTAG device to match (default: xc7z020_1)
#
# For a board on a REMOTE machine, run hw_server there and pass
#     --url <remote-ip>:3121
#-------------------------------------------------------------------------------

set proj_name "can_node"
set top       "can_node_top"

set script_dir [file normalize [file dirname [info script]]]   ;# .../vivado
set root_dir   [file normalize "$script_dir/.."]               ;# repo root
set proj_dir   "$script_dir/$proj_name"

# ── Defaults ────────────────────────────────────────────────────────────────
set bit_file  ""
set hw_url    "localhost:3121"
set dev_match "xc7z020_1"

for {set i 0} {$i < [llength $argv]} {incr i} {
    switch -exact -- [lindex $argv $i] {
        "--bit"    { incr i; set bit_file  [lindex $argv $i] }
        "--url"    { incr i; set hw_url    [lindex $argv $i] }
        "--device" { incr i; set dev_match [lindex $argv $i] }
        default    { puts "WARNING: unknown arg '[lindex $argv $i]'" }
    }
}

# ── Locate the bitstream ────────────────────────────────────────────────────
if {$bit_file eq ""} {
    set candidates [list \
        "$root_dir/build/$proj_name.bit" \
        "$proj_dir/$proj_name.runs/impl_1/${top}.bit"]
    foreach c $candidates {
        if {[file exists $c]} { set bit_file $c; break }
    }
}
if {$bit_file eq "" || ![file exists $bit_file]} {
    error "ERROR: no bitstream found. Run build.tcl first, or pass --bit <path>."
}
set bit_file [file normalize $bit_file]
puts "INFO: programming with $bit_file"

# ── Connect to the hardware ─────────────────────────────────────────────────
open_hw_manager
if {[catch {connect_hw_server -url $hw_url} err]} {
    error "ERROR: cannot reach hw_server at $hw_url ($err).\
           Is the board connected / hw_server running?"
}

set targets [get_hw_targets]
if {[llength $targets] == 0} {
    error "ERROR: no JTAG targets found. Check cable, power, and drivers."
}
open_hw_target [lindex $targets 0]

# ── Select the PL device ────────────────────────────────────────────────────
set dev [lindex [get_hw_devices *$dev_match*] 0]
if {$dev eq ""} {
    puts "WARNING: device '$dev_match' not found; chain = [get_hw_devices]"
    set dev [lindex [get_hw_devices] 0]
}
current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev

# ── Program ─────────────────────────────────────────────────────────────────
set_property PROGRAM.FILE $bit_file $dev
program_hw_devices $dev
refresh_hw_device $dev

puts "============================================================"
puts " Programmed $dev with [file tail $bit_file]"
puts "============================================================"

close_hw_target
disconnect_hw_server
close_hw_manager
