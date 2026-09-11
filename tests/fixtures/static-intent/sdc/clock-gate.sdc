create_clock -name source_clk -period 10.0 [get_ports clk]
create_generated_clock -name gated_clk -source [get_ports clk] -combinational [get_ports gated_clk]
set_clock_uncertainty 0.1 [get_clocks source_clk]
set_input_delay 0.5 -clock source_clk [get_ports {enable test_enable}]
