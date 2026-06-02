## PYNQ-Z1 constraints for can_node  (Zynq-7000, xc7z020clg400-1)
## Pin assignments follow Digilent's official PYNQ-Z1 Master XDC.
## Only the signals used by can_node_top are enabled; uncomment more as needed.

## ─── System clock : 125 MHz on H16 ──────────────────────────────────────
set_property -dict { PACKAGE_PIN H16  IOSTANDARD LVCMOS33 } [get_ports { sysclk }];
create_clock -add -name sys_clk_pin -period 8.00 -waveform {0 4} [get_ports { sysclk }];

## ─── Reset : push-button BTN0 (D19) ─────────────────────────────────────
set_property -dict { PACKAGE_PIN D19  IOSTANDARD LVCMOS33 } [get_ports { btn_rst }];

## ─── User LEDs LD0..LD3 ─────────────────────────────────────────────────
set_property -dict { PACKAGE_PIN R14  IOSTANDARD LVCMOS33 } [get_ports { led[0] }];
set_property -dict { PACKAGE_PIN P14  IOSTANDARD LVCMOS33 } [get_ports { led[1] }];
set_property -dict { PACKAGE_PIN N16  IOSTANDARD LVCMOS33 } [get_ports { led[2] }];
set_property -dict { PACKAGE_PIN M14  IOSTANDARD LVCMOS33 } [get_ports { led[3] }];

## ─── CAN transceiver on PMOD JA ─────────────────────────────────────────
## Wire a 3.3 V CAN transceiver (e.g. SN65HVD230 PMOD) to these pins.
##   can_rx  -> JA1 (Y18)   transceiver RXD output
##   can_tx  -> JA2 (Y19)   transceiver TXD input
set_property -dict { PACKAGE_PIN Y18  IOSTANDARD LVCMOS33 } [get_ports { can_rx }];
set_property -dict { PACKAGE_PIN Y19  IOSTANDARD LVCMOS33 } [get_ports { can_tx }];

## ─── Remaining PMOD JA pins (free) ──────────────────────────────────────
# JA3  Y16 | JA4  Y17 | JA7  U18 | JA8  U19 | JA9  W18 | JA10 W19

## ─── Bitstream / config hygiene ─────────────────────────────────────────
set_property CFGBVS VCCO        [current_design];
set_property CONFIG_VOLTAGE 3.3 [current_design];
