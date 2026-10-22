## ============================================================================
## Constraints for PYNQ-Z2 Board (XC7Z020-1CLG400C)
## 5-Stage In-Order RV64 Core with UART MMIO
## ============================================================================

## ----------------------------------------------------------------------------
## 125 MHz System Clock
## ----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN H16   IOSTANDARD LVCMOS33 } [get_ports { sys_clk }];
create_clock -add -name sys_clk_pin -period 8.00 -waveform {0 4} [get_ports { sys_clk }];

## ----------------------------------------------------------------------------
## Push Button Reset: BTN0 (Active-High)
## ----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN D19   IOSTANDARD LVCMOS33 } [get_ports { sys_rst }];

## ----------------------------------------------------------------------------
## Physical UART Interface: Arduino Header Pins D0 (RX) & D1 (TX)
## Connect external USB-UART adapter:
##   - Adapter TX -> PYNQ Pin Y14 (Arduino D0 / uart_rx_pin)
##   - Adapter RX <- PYNQ Pin W14 (Arduino D1 / uart_tx_pin)
##   - Adapter GND -> PYNQ GND
## ----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN Y14   IOSTANDARD LVCMOS33 } [get_ports { uart_rx_pin }];
set_property -dict { PACKAGE_PIN W14   IOSTANDARD LVCMOS33 } [get_ports { uart_tx_pin }];

## ----------------------------------------------------------------------------
## User Green LEDs (LD0 - LD3)
##   LD0: 1 Hz Heartbeat
##   LD1: Core Halted (WFI executed)
##   LD2: Memory/UART Bus Activity
##   LD3: PLL Clock Locked
## ----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN R14   IOSTANDARD LVCMOS33 } [get_ports { leds[0] }];
set_property -dict { PACKAGE_PIN P14   IOSTANDARD LVCMOS33 } [get_ports { leds[1] }];
set_property -dict { PACKAGE_PIN N16   IOSTANDARD LVCMOS33 } [get_ports { leds[2] }];
set_property -dict { PACKAGE_PIN M16   IOSTANDARD LVCMOS33 } [get_ports { leds[3] }];

## ----------------------------------------------------------------------------
## Configuration & Voltage Settings
## ----------------------------------------------------------------------------
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
