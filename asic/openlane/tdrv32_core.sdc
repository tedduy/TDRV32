create_clock -name core_clk -period 30.0 [get_ports i_clk]
set core_clock [get_clocks core_clk]

set_clock_uncertainty -setup 1.25 $core_clock
set_clock_uncertainty -hold 0.05 $core_clock
set_false_path -from [get_ports i_arst_n]

set data_inputs [get_ports {
    i_irq_software i_irq_timer i_irq_external i_time
    i_imem_rdata i_imem_ready i_imem_error
    i_dmem_rdata i_dmem_ready i_dmem_error
}]
set_input_delay 2.5 -clock $core_clock $data_inputs

set_output_delay 2.5 -clock $core_clock [all_outputs]
set_load 0.05 [all_outputs]

set_max_transition 2.5 [current_design]
