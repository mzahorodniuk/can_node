#-------------------------------------------------------------------------------
# build_ila.tcl -- non-project build of can_node_top with an auto-inserted ILA.
#
#   Run from the project root:
#       vivado -mode batch -source tcl/build_ila.tcl
#
# It reads the VHDL + XDC, synthesizes, then DISCOVERS every net tagged with
# `mark_debug` in the HDL and wires each one to a single ILA core (one probe per
# signal, bus widths handled automatically). No net names are hard-coded, so the
# probe list always matches whatever you marked in the source.
#
# Outputs (in build/):
#   can_node_top.bit   -- bitstream with the ILA baked in
#   can_node_top.ltx   -- debug-probes file (gives the ILA signal names at runtime)
#-------------------------------------------------------------------------------

# ---- settings -- edit PART/paths if your layout differs ----------------------
set PART  xc7z020clg400-1                                   ;# PYNQ-Z1 (Zynq-7020)
set TOP   can_node_top
set ROOT  [file normalize [file dirname [info script]]/..]  ;# repo root (this is in tcl/)
set SRC   $ROOT/src
set XDC   $ROOT/constraints/pynq_z1.xdc
set OUT   $ROOT/build
set DEPTH 4096                                              ;# ILA sample depth
# ------------------------------------------------------------------------------

file mkdir $OUT

# ---- read sources & synthesize -----------------------------------------------
read_vhdl [glob $SRC/*.vhd]
read_xdc  $XDC
synth_design -top $TOP -part $PART
opt_design

#-------------------------------------------------------------------------------
# ILA insertion -- everything below is generic; it adapts to the marked nets.
#-------------------------------------------------------------------------------

# Find the global clock net (single-clock design -> one BUFG).
set bufgs [get_cells -hierarchical -filter {REF_NAME == BUFG}]
if {[llength $bufgs] == 0} {
  error "No BUFG found -- cannot determine the ILA sample clock."
}
set clk_net [get_nets -of_objects [get_pins -filter {REF_PIN_NAME == O} -of_objects [lindex $bufgs 0]]]
puts "ILA: sample clock net = $clk_net"

# Collect the mark_debug nets and group bus bits (foo[0],foo[1],... -> foo).
set marked [get_nets -hierarchical -filter {MARK_DEBUG}]
if {[llength $marked] == 0} {
  error "No mark_debug nets found -- did you keep the attributes in the HDL?"
}
array unset groups
foreach n $marked {
  if {[regexp {^(.*)\[([0-9]+)\]$} $n -> base idx]} {
    lappend groups($base) [list $idx $n]
  } else {
    set groups($n) [list [list 0 $n]]
  }
}

# Create one ILA core.
create_debug_core u_ila_0 ila
set_property C_DATA_DEPTH        $DEPTH [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN         false  [get_debug_cores u_ila_0]
set_property C_TRIGOUT_EN        false  [get_debug_cores u_ila_0]
set_property C_ADV_TRIGGER       false  [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES 0      [get_debug_cores u_ila_0]
set_property C_EN_STRG_QUAL      false  [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU      true [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU_CNT  1    [get_debug_cores u_ila_0]

# Sample clock.
set_property PORT_WIDTH 1 [get_debug_ports u_ila_0/clk]
connect_debug_port u_ila_0/clk [get_nets $clk_net]

# One probe per marked signal (probe0 already exists; create the rest).
set i 0
foreach base [lsort [array names groups]] {
  set bits [lsort -integer -index 0 $groups($base)]
  set nets {}
  foreach pair $bits { lappend nets [lindex $pair 1] }
  set w [llength $nets]
  if {$i > 0} { create_debug_port u_ila_0 probe }
  set port u_ila_0/probe$i
  set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports $port]
  set_property PORT_WIDTH $w               [get_debug_ports $port]
  connect_debug_port $port [get_nets $nets]
  puts [format "ILA: probe%-2d <- %-28s (%d bit%s)" $i $base $w [expr {$w==1?"":"s"}]]
  incr i
}

# Debug hub clock (auto-created with the first core).
catch {
  set_property C_CLK_INPUT_FREQ_HZ   125000000 [get_debug_cores dbg_hub]
  set_property C_ENABLE_CLK_DIVIDER   false     [get_debug_cores dbg_hub]
  set_property C_USER_SCAN_CHAIN      1         [get_debug_cores dbg_hub]
  connect_debug_port dbg_hub/clk [get_nets $clk_net]
}

#-------------------------------------------------------------------------------
# place / route / bitstream
#-------------------------------------------------------------------------------
place_design
route_design
write_bitstream    -force $OUT/${TOP}.bit
write_debug_probes -force $OUT/${TOP}.ltx
puts "DONE -> $OUT/${TOP}.bit  +  $OUT/${TOP}.ltx"
