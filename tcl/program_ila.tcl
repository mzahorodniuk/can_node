#-------------------------------------------------------------------------------
# program_ila.tcl -- program the PYNQ-Z1 PL over JTAG and arm the ILA to catch a
# CAN frame, triggering on rx_valid == 1.
#
#   Run after build_ila.tcl, with the board plugged in via USB:
#       vivado -mode tcl -source tcl/program_ila.tcl
#
# It connects to the board, loads the .bit + .ltx, sets the trigger, arms the
# ILA, then waits. Send a frame from the STM32 publisher and the waveform
# uploads automatically. If it triggers, messages are arriving and decoding.
#-------------------------------------------------------------------------------

set ROOT [file normalize [file dirname [info script]]/..]
set BIT  $ROOT/build/can_node_top.bit
set LTX  $ROOT/build/can_node_top.ltx

# ---- connect & program -------------------------------------------------------
open_hw_manager
connect_hw_server
open_hw_target                                  ;# auto-finds the PYNQ-Z1 USB-JTAG
current_hw_device [lindex [get_hw_devices] 0]
set dev [current_hw_device]

set_property PROBES.FILE      $LTX $dev
set_property FULL_PROBES.FILE $LTX $dev
set_property PROGRAM.FILE     $BIT $dev
program_hw_devices $dev
refresh_hw_device  $dev

# ---- configure & arm the ILA -------------------------------------------------
set ila [get_hw_ilas -of_objects $dev]

# Capture window: 256 samples before the trigger, the rest after.
set_property CONTROL.TRIGGER_POSITION 256    $ila
set_property CONTROL.DATA_DEPTH       4096   $ila

# Trigger: rx_valid goes high (a good frame completed).
set rxv [get_hw_probes *rx_valid* -of_objects $ila]
set_property TRIGGER_COMPARE_VALUE eq1'b1 $rxv

run_hw_ila $ila
puts "============================================================"
puts " ILA armed on rx_valid==1."
puts " Now send a CAN frame from the STM32 publisher (0x100/.../)."
puts "============================================================"
wait_on_hw_ila $ila
display_hw_ila_data [upload_hw_ila_data $ila]
puts "Triggered -- waveform uploaded. Read rx_id / rx_dlc / rx_data at the marker."

# --- To debug the FAILING case instead (bits arrive but no good frame),
# --- comment out the rx_valid trigger above and use a falling edge on rx_sync:
#   set rxs [get_hw_probes *rx_sync* -of_objects $ila]
#   set_property TRIGGER_COMPARE_VALUE eq1'b0 $rxs
# --- then watch `state` walk through the frame and where it stalls.
