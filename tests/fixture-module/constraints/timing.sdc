create_clock -name core_clk -period 10.000 [get_ports clk_i]
set_input_delay 1.000 -clock core_clk [remove_from_collection [all_inputs] [get_ports clk_i]]
set_output_delay 1.000 -clock core_clk [all_outputs]
set_false_path -from [get_ports rst_ni]
