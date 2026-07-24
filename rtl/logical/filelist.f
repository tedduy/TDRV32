+incdir+rtl/logical/common
+incdir+rtl/logical/stages/fetch
+incdir+rtl/logical/stages/decode
+incdir+rtl/logical/stages/execute
+incdir+rtl/logical/stages/memory
+incdir+rtl/logical/stages/system
+incdir+rtl/logical/pipeline
+incdir+rtl/logical/hazard
+incdir+rtl/logical/bus

rtl/logical/common/adder_n_bit.sv
rtl/logical/common/core_sleep_gate.sv
rtl/logical/common/mux2to1.sv
rtl/logical/common/mux3to1.sv
rtl/logical/common/mux4to1.sv

rtl/logical/stages/fetch/program_counter.sv
rtl/logical/stages/fetch/instruction_memory.sv
rtl/logical/stages/fetch/rv32c_fetch_buffer.sv

rtl/logical/stages/decode/control_unit.sv
rtl/logical/stages/decode/immediate_generator.sv
rtl/logical/stages/decode/register_file.sv
rtl/logical/stages/decode/rv32c_decompressor.sv

rtl/logical/stages/execute/alu_unit.sv
rtl/logical/stages/execute/iterative_multiplier.sv
rtl/logical/stages/execute/iterative_divider.sv
rtl/logical/stages/execute/mdu_unit.sv
rtl/logical/stages/execute/branch_unit.sv
rtl/logical/stages/execute/jump_unit.sv

rtl/logical/stages/memory/load_store_unit.sv
rtl/logical/stages/memory/data_memory.sv

rtl/logical/stages/system/csr_file.sv

rtl/logical/pipeline/if_id_register.sv
rtl/logical/pipeline/id_ex_register.sv
rtl/logical/pipeline/ex_mem_register.sv
rtl/logical/pipeline/mem_wb_register.sv
rtl/logical/pipeline/tdrv32_rvfi_shadow.sv
rtl/logical/pipeline/tdrv32_pipeline.sv

rtl/logical/hazard/forwarding_unit.sv
rtl/logical/hazard/hazard_detection_unit.sv

rtl/logical/bus/native_to_ahb_lite.sv
rtl/logical/tdrv32_core.sv
rtl/logical/tdrv32_top.sv
rtl/logical/tdrv32_asic_wrapper.sv
