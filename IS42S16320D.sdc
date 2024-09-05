#**************************************************************
# Create Clock
#**************************************************************
create_clock -period "10.0 MHz" [get_ports ADC_CLK_10]
create_clock -period "50.0 MHz" [get_ports MAX10_CLK1_50]
create_clock -period "50.0 MHz" [get_ports MAX10_CLK2_50]

# SDRAM CLK (100 MHz)
create_generated_clock -source [get_pins Clk_DRAM_PLL|*|clk[1] ] \
                       -name opClk_DRAM [get_ports opClk_DRAM]

derive_pll_clocks
derive_clock_uncertainty

#**************************************************************
# Set Input Delay
#**************************************************************
# suppose +- 100 ps skew
# Board Delay (Data) + Propagation Delay - Board Delay (Clock)
# max 5.4(max) +0.4(trace delay) +0.1 = 5.9
# min 2.7(min) +0.4(trace delay) -0.1 = 3.0
set_input_delay -max -clock opClk_DRAM 5.9 [get_ports bpDRAM*]
set_input_delay -min -clock opClk_DRAM 3.0 [get_ports bpDRAM*]

# shift-window (clk[0] is also 100 MHz, but with -3 ns phase shift)
set_multicycle_path -from [get_clocks opClk_DRAM] \
                    -to   [get_clocks Clk_DRAM_PLL|*|clk[0] ] \
                    -setup 2

#**************************************************************
# Set Output Delay
#**************************************************************
# suppose +- 100 ps skew
# max : Board Delay (Data) - Board Delay (Clock) + tsu (External Device)
# min : Board Delay (Data) - Board Delay (Clock) - th (External Device)
# max  1.5 +0.1 =  1.6
# min -0.8 -0.1 = -0.9
set_output_delay -max -clock opClk_DRAM  1.6 [get_ports { bpDRAM* opDRAM* }]
set_output_delay -min -clock opClk_DRAM -0.9 [get_ports { bpDRAM* opDRAM* }]

