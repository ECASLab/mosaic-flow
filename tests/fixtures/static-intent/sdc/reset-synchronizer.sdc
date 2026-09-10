create_clock -name destination_clk -period 10.0 [get_ports clk]
set_clock_uncertainty 0.1 [get_clocks destination_clk]
set_output_delay 0.5 -clock destination_clk [get_ports rst_sync_n]
