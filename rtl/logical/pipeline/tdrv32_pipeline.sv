// =============================================================================
// RV32IMC five-stage pipeline implementation.
// =============================================================================

module tdrv32_pipeline #(
    parameter N = 32,
    parameter REG_DEPTH = 32,
    parameter logic [N-1:0] RESET_VECTOR = '0,
    parameter logic [N-1:0] MVENDOR_ID = '0,
    parameter logic [N-1:0] MARCH_ID = '0,
    parameter logic [N-1:0] MIMP_ID = '0,
    parameter logic [N-1:0] HART_ID = '0,
    parameter logic [N-1:0] CONFIG_PTR = '0,
    parameter logic ENABLE_DEBUG_SHADOWS = 1'b0
)(
    input  logic i_clk,
    input  logic i_arst_n,

    // Synchronous machine-mode interrupt requests
    input  logic i_irq_software,
    input  logic i_irq_timer,
    input  logic i_irq_external,
    input  logic [63:0] i_time,

    output logic o_core_sleep,
    output logic o_fence_i,

    // External instruction memory interface
    output logic         o_imem_valid,
    output logic [N-1:0] o_imem_addr,
    input  logic [N-1:0] i_imem_rdata,
    input  logic         i_imem_ready,
    // Error qualifies an accepted response (valid && ready).
    input  logic         i_imem_error,

    // External data memory interface
    output logic         o_dmem_valid,
    output logic         o_dmem_read,
    output logic         o_dmem_write,
    output logic [N-1:0] o_dmem_addr,
    output logic [N-1:0] o_dmem_wdata,
    output logic [3:0]   o_dmem_wstrb,
    output logic [1:0]   o_dmem_size,
    input  logic [N-1:0] i_dmem_rdata,
    input  logic         i_dmem_ready,
    // Error qualifies an accepted response (valid && ready).
    input  logic         i_dmem_error,

    // Architectural commit/retire interface
    output logic         o_commit_valid,
    output logic [N-1:0] o_commit_pc,
    output logic [N-1:0] o_commit_instruction,
    output logic         o_commit_rd_write,
    output logic [4:0]   o_commit_rd_addr,
    output logic [N-1:0] o_commit_rd_data,
    output logic         o_commit_mem_write,
    output logic [N-1:0] o_commit_mem_addr,
    output logic [N-1:0] o_commit_mem_wdata,
    output logic [3:0]   o_commit_mem_wstrb,

`ifdef RISCV_FORMAL
    // RISC-V Formal Interface (one in-order retirement channel).
    output logic         rvfi_valid,
    output logic [63:0]  rvfi_order,
    output logic [N-1:0] rvfi_insn,
    output logic         rvfi_trap,
    output logic         rvfi_halt,
    output logic         rvfi_intr,
    output logic [1:0]   rvfi_mode,
    output logic [1:0]   rvfi_ixl,
    output logic [4:0]   rvfi_rs1_addr,
    output logic [4:0]   rvfi_rs2_addr,
    output logic [N-1:0] rvfi_rs1_rdata,
    output logic [N-1:0] rvfi_rs2_rdata,
    output logic [4:0]   rvfi_rd_addr,
    output logic [N-1:0] rvfi_rd_wdata,
    output logic [N-1:0] rvfi_pc_rdata,
    output logic [N-1:0] rvfi_pc_wdata,
    output logic [N-1:0] rvfi_mem_addr,
    output logic [3:0]   rvfi_mem_rmask,
    output logic [3:0]   rvfi_mem_wmask,
    output logic [N-1:0] rvfi_mem_rdata,
    output logic [N-1:0] rvfi_mem_wdata,
`endif
    
    // Debug/Test outputs
    output logic [N-1:0] o_debug_pc,
    output logic [N-1:0] o_debug_instruction,
    // Pure observability ports do not influence architectural behavior.
    /* verilator coverage_off */
    output logic [N-1:0] o_debug_rs1_data,
    output logic [N-1:0] o_debug_rs2_data,
    /* verilator coverage_on */
    output logic [N-1:0] o_debug_alu_operand_b,
    output logic [N-1:0] o_debug_branch_target,
    output logic [N-1:0] o_debug_alu_result,
    output logic [N-1:0] o_debug_wb_data,
    output logic [4:0]   o_debug_rd_addr,
    output logic         o_debug_rd_write,
    output logic         o_debug_mem_write,
    output logic         o_debug_mem_read,
    output logic         o_debug_branch_taken,
    output logic [N-1:0] o_debug_mem_addr,
    output logic [N-1:0] o_debug_mem_wdata,
    output logic [N-1:0] o_debug_mem_rdata,
    output logic         o_debug_jal,
    output logic         o_debug_jalr,
    // Pipeline control signals
    output logic         o_debug_stall,
    output logic         o_debug_flush,
    // Additional debug signals
    output logic [N-1:0] o_debug_immediate,
    output logic         o_debug_alu_uses_immediate
);

    // ==========================================================================
    // IF Stage Signals
    // ==========================================================================
    logic [N-1:0] if_pc_current, if_pc_next, if_pc_sequential;
    logic [N-1:0] if_instruction, if_raw_instruction;
    logic         if_complete, if_compressed, if_pc_increment_2;
    logic         if_access_fault, if_consume;
    logic         if_request_valid;
    
    // ==========================================================================
    // IF/ID Pipeline Register Signals
    // ==========================================================================
    logic         id_valid;
    logic         id_instruction_access_fault;
    logic         id_compressed;
    logic [N-1:0] id_pc, id_instruction, id_raw_instruction;
    
    // ==========================================================================
    // ID Stage Signals
    // ==========================================================================
    logic [4:0]  id_rs1_addr, id_rs2_addr, id_rd_addr;
    logic [N-1:0] id_rs1_data, id_rs2_data;
    logic [N-1:0] id_immediate;
    
    // ID Control signals
    logic        id_reg_write, id_mem_read, id_mem_write;
    logic [1:0]  id_wb_sel, id_pc_sel;
    logic        id_alu_src, id_alu_a_sel;
    logic [3:0]  id_alu_ctrl;
    logic        id_branch_en;
    logic [2:0]  id_branch_type;
    logic [2:0]  id_mem_type;
    logic        id_jal, id_jalr;
    logic        id_csr_en, id_csr_imm;
    logic [1:0]  id_csr_op;
    logic        id_ecall, id_ebreak, id_mret, id_wfi, id_fence_i, id_illegal;
    
    // ==========================================================================
    // ID/EX Pipeline Register Signals
    // ==========================================================================
    logic         ex_valid;
    logic         ex_instruction_access_fault;
    logic         ex_compressed;
    logic [N-1:0] ex_pc, ex_instruction, ex_raw_instruction;
    logic [N-1:0] ex_rs1_data, ex_rs2_data, ex_immediate;
    logic [4:0]   ex_rs1_addr, ex_rs2_addr, ex_rd_addr;
    logic         ex_reg_write, ex_mem_read, ex_mem_write;
    // Consumed by the RVFI shadow only when RISCV_FORMAL is enabled.
    /* verilator lint_off UNUSEDSIGNAL */
    logic         ex_rs1_read, ex_rs2_read;
    /* verilator lint_on UNUSEDSIGNAL */
    logic [1:0]   ex_wb_sel, ex_pc_sel;
    logic         ex_alu_src, ex_alu_a_sel;
    logic [3:0]   ex_alu_ctrl;
    logic         ex_branch_en;
    logic [2:0]   ex_branch_type, ex_mem_type;
    logic         ex_jal, ex_jalr;
    logic         ex_csr_en, ex_csr_imm;
    logic [1:0]   ex_csr_op;
    logic         ex_ecall, ex_ebreak, ex_mret, ex_wfi, ex_fence_i, ex_illegal;
    // ==========================================================================
    // EX Stage Signals
    // ==========================================================================
    logic [N-1:0] ex_alu_operand_a, ex_alu_operand_b;
    logic [N-1:0] ex_alu_operand_a_forwarded;
    logic [N-1:0] ex_alu_result;
    logic [N-1:0] ex_pc_branch_target;
    logic         ex_branch_taken;
    logic [N-1:0] ex_jump_target, ex_return_addr;
    logic [N-1:0] ex_rs2_data_forwarded;  // For store operations
    logic [N-1:0] ex_data_addr;
    logic [N-1:0] ex_mdu_result;
    logic [N-1:0] ex_result;
    logic         ex_mdu_active, mdu_stall;

    // Machine-mode CSR/trap signals
    logic [11:0]  ex_csr_addr;
    logic [N-1:0] ex_csr_rdata, ex_csr_operand, ex_csr_wdata;
    logic [N-1:0] csr_mtvec, csr_mepc;
    logic         csr_write, csr_write_intent;
    logic         csr_valid, csr_writable, csr_access_illegal;
    logic         ex_sync_trap, irq_take, trap_enter, mret_taken, wfi_sleep;
    logic         fence_i_taken, system_redirect, core_sleep;
    logic         csr_irq_pending, csr_wake_pending;
    logic [N-1:0] csr_irq_cause, trap_cause, trap_value;
    logic [N-1:0] trap_pc;
    logic [N-1:0] system_redirect_pc;
    logic [N-1:0] trap_vector_base, trap_vector_offset, trap_vector_pc;
    logic [N-1:0] control_transfer_target;
    /* verilator coverage_off */
    logic         instruction_addr_misaligned;
    /* verilator coverage_on */
    logic         data_addr_misaligned;
    logic         illegal_exception, load_misaligned_exception;
    logic         store_misaligned_exception;
    logic         instruction_access_exception;
    logic         load_access_exception, store_access_exception;
    logic         data_access_exception;
    
    // ==========================================================================
    // EX/MEM Pipeline Register Signals
    // ==========================================================================
    logic         mem_valid;
    logic [N-1:0] mem_pc, mem_instruction;
    logic [N-1:0] mem_alu_result, mem_rs2_data;
    logic [N-1:0] mem_immediate;
    logic [4:0]   mem_rd_addr;
    logic         mem_branch_taken;
    logic         mem_reg_write, mem_mem_read, mem_mem_write;
    logic [2:0]   mem_mem_type;
    logic         mem_jal, mem_jalr;
    // ==========================================================================
    // MEM Stage Signals
    // ==========================================================================
    logic [N-1:0] mem_load_data, mem_store_data, mem_wb_data;
    logic [3:0]   mem_byte_enable;
    
    // ==========================================================================
    // MEM/WB Pipeline Register Signals
    // ==========================================================================
    logic         wb_valid;
    logic [N-1:0] wb_pc, wb_instruction;
    logic [N-1:0] wb_alu_result, wb_immediate;
    logic [4:0]   wb_rd_addr;
    logic         wb_reg_write;
    logic         wb_mem_write;
    logic [N-1:0] wb_mem_addr, wb_mem_wdata;
    logic [3:0]   wb_mem_wstrb;
    logic         wb_jal, wb_jalr;
    logic         wb_branch_taken;
    // ==========================================================================
    // WB Stage Signals
    // ==========================================================================
    logic [N-1:0] wb_data;
    
    // ==========================================================================
    // Hazard Detection Signals
    // ==========================================================================
    logic stall_pc, stall_if_id, flush_id_ex, flush_if_id;
    logic hazard_stall_pc, hazard_stall_if_id;
    logic hazard_flush_id_ex, hazard_flush_if_id;
    logic csr_order_stall;
    logic pipeline_flush_id_ex, pipeline_flush_if_id;
    logic imem_wait, dmem_wait, bus_stall, pipeline_stall, pipeline_advance;
    logic mem_wb_fire, mem_wb_consumed_q;
    logic mem_stage_complete, mem_access_error;
    logic pc_hold;
    logic dmem_request, dmem_complete, dmem_error_pending;
    logic [N-1:0] dmem_rdata_latched, dmem_response_rdata;
    
    // ==========================================================================
    // Forwarding Signals
    // ==========================================================================
    logic [1:0] forward_a, forward_b;
    logic [N-1:0] mem_forward_data;

`ifdef RISCV_FORMAL
    // RVFI shadow path is implemented by the tdrv32_rvfi_shadow sub-module.
    // See the instantiation after the commit output assignments below.
`endif
    
    // ==========================================================================
    // Debug Output Assignments
    // ==========================================================================

    // PC and instruction already travel through the architectural MEM/WB
    // register.  Reuse that payload instead of maintaining a duplicate
    // four-stage debug pipeline.
    assign o_debug_pc          = wb_pc;
    assign o_debug_instruction = wb_instruction;

    // Original source operands are useful only for legacy waveform displays.
    // Compile their shadow pipeline out of area-focused MCU configurations.
    generate
        if (ENABLE_DEBUG_SHADOWS) begin : g_debug_operand_shadows
            logic [N-1:0] ex_rd1_shadow, ex_rd2_shadow;
            logic [N-1:0] mem_rd1_shadow, mem_rd2_shadow;
            logic [N-1:0] wb_rd1_shadow, wb_rd2_shadow;

            always_ff @(posedge i_clk or negedge i_arst_n) begin
                if (!i_arst_n) begin
                    ex_rd1_shadow  <= '0;
                    ex_rd2_shadow  <= '0;
                    mem_rd1_shadow <= '0;
                    mem_rd2_shadow <= '0;
                    wb_rd1_shadow  <= '0;
                    wb_rd2_shadow  <= '0;
                end else if (pipeline_advance) begin
                    if (pipeline_flush_id_ex) begin
                        ex_rd1_shadow <= '0;
                        ex_rd2_shadow <= '0;
                    end else begin
                        ex_rd1_shadow <= id_rs1_data;
                        ex_rd2_shadow <= id_rs2_data;
                    end
                    mem_rd1_shadow <= ex_rd1_shadow;
                    mem_rd2_shadow <= ex_rd2_shadow;
                    wb_rd1_shadow  <= mem_rd1_shadow;
                    wb_rd2_shadow  <= mem_rd2_shadow;
                end
            end

            assign o_debug_rs1_data = wb_rd1_shadow;
            assign o_debug_rs2_data = wb_rd2_shadow;
        end else begin : g_no_debug_operand_shadows
            assign o_debug_rs1_data = '0;
            assign o_debug_rs2_data = '0;
        end
    endgenerate

    assign o_debug_alu_operand_b           = ex_alu_operand_b;
    assign o_debug_branch_target           = ex_pc_branch_target;
    assign o_debug_alu_result          = wb_alu_result;
    assign o_debug_wb_data             = wb_data;
    assign o_debug_rd_addr             = wb_rd_addr;
    assign o_debug_rd_write            = wb_valid && wb_reg_write;
    assign o_debug_mem_write           = mem_mem_write;
    assign o_debug_mem_read            = mem_mem_read;
    assign o_debug_branch_taken        = wb_branch_taken;
    assign o_debug_jal          = wb_jal;
    assign o_debug_jalr         = wb_jalr;
    
    assign o_debug_mem_addr     = mem_alu_result;
    assign o_debug_mem_wdata    = mem_store_data;
    assign o_debug_mem_rdata    = mem_load_data;

    assign o_imem_valid   = i_arst_n && !core_sleep && if_request_valid;
    assign o_core_sleep   = core_sleep;
    assign o_fence_i      = fence_i_taken;
    assign imem_wait      = o_imem_valid && !if_complete;

    assign dmem_request   = mem_mem_read || mem_mem_write;
    assign o_dmem_valid   = dmem_request && !dmem_complete;
    assign o_dmem_read    = mem_mem_read;
    assign o_dmem_write   = mem_mem_write;
    assign o_dmem_addr    = mem_alu_result;
    assign o_dmem_wdata   = mem_store_data;
    assign o_dmem_wstrb   = mem_byte_enable;
    assign o_dmem_size    = (mem_mem_type == 3'b010) ? 2'd2 :
                            ((mem_mem_type == 3'b001) ||
                             (mem_mem_type == 3'b101)) ? 2'd1 : 2'd0;
    assign dmem_response_rdata = dmem_complete ? dmem_rdata_latched
                                                : i_dmem_rdata;
    assign dmem_wait      = o_dmem_valid && !i_dmem_ready;
    assign bus_stall      = imem_wait || dmem_wait;
    // One global hold condition freezes every architectural pipeline boundary.
    // Redirect/trap signals are generated only while pipeline_advance is true.
    assign pipeline_stall   = bus_stall || mdu_stall;
    assign pipeline_advance = !pipeline_stall;
    assign o_debug_stall        = stall_if_id || pipeline_stall;
    assign o_debug_flush        = pipeline_flush_id_ex | pipeline_flush_if_id;
    assign o_debug_immediate    = wb_immediate;
    assign o_debug_alu_uses_immediate       = ex_alu_src;

    // WB is an always-ready sink. Once a packet reaches this elastic boundary,
    // younger instruction/data bus backpressure cannot delay its retirement.
    assign o_commit_valid       = wb_valid;
    assign o_commit_pc          = wb_pc;
    assign o_commit_instruction = wb_instruction;
    assign o_commit_rd_write    = o_commit_valid && wb_reg_write && (wb_rd_addr != 5'd0);
    assign o_commit_rd_addr     = wb_rd_addr;
    assign o_commit_rd_data     = wb_data;
    assign o_commit_mem_write   = o_commit_valid && wb_mem_write;
    assign o_commit_mem_addr    = wb_mem_addr;
    assign o_commit_mem_wdata   = wb_mem_wdata;
    assign o_commit_mem_wstrb   = wb_mem_wstrb;

`ifdef RISCV_FORMAL
    tdrv32_rvfi_shadow #(.N(N)) u_rvfi_shadow (
        .i_clk(i_clk),
        .i_arst_n(i_arst_n),
        .i_pipeline_stall(pipeline_stall),
        .i_mem_wb_advance(1'b1),
        .i_mem_wb_fire(mem_wb_fire),
        .i_trap_enter(trap_enter),
        .i_ex_sync_trap(ex_sync_trap),
        .i_data_access_exception(data_access_exception),
        .i_ex_valid(ex_valid),
        .i_ex_pc(ex_pc),
        .i_ex_compressed(ex_compressed),
        .i_ex_raw_instruction(ex_raw_instruction),
        .i_ex_rs1_addr(ex_rs1_addr),
        .i_ex_rs2_addr(ex_rs2_addr),
        .i_ex_rs1_read(ex_rs1_read),
        .i_ex_rs2_read(ex_rs2_read),
        .i_ex_alu_operand_a_forwarded(ex_alu_operand_a_forwarded),
        .i_ex_rs2_data_forwarded(ex_rs2_data_forwarded),
        .i_ex_data_addr(ex_data_addr),
        .i_ex_branch_taken(ex_branch_taken),
        .i_ex_jal(ex_jal),
        .i_ex_jalr(ex_jalr),
        .i_ex_mret(ex_mret),
        .i_control_transfer_target(control_transfer_target),
        .i_csr_mepc(csr_mepc),
        .i_mem_pc(mem_pc),
        .i_mem_instruction(mem_instruction),
        .i_mem_alu_result(mem_alu_result),
        .i_mem_mem_read(mem_mem_read),
        .i_mem_mem_write(mem_mem_write),
        .i_mem_mem_type(mem_mem_type),
        .i_mem_store_operand(mem_store_data_forwarded),
        .i_dmem_response_rdata(dmem_response_rdata),
        .i_commit_valid(o_commit_valid),
        .i_commit_rd_write(o_commit_rd_write),
        .i_wb_instruction(wb_instruction),
        .i_wb_pc(wb_pc),
        .i_wb_rd_addr(wb_rd_addr),
        .i_wb_data(wb_data),
        .i_wb_mem_write(wb_mem_write),
        .i_wb_mem_addr(wb_mem_addr),
        .i_wb_mem_wdata(wb_mem_wdata),
        .i_wb_mem_wstrb(wb_mem_wstrb),
        .o_rvfi_valid(rvfi_valid),
        .o_rvfi_order(rvfi_order),
        .o_rvfi_insn(rvfi_insn),
        .o_rvfi_trap(rvfi_trap),
        .o_rvfi_halt(rvfi_halt),
        .o_rvfi_intr(rvfi_intr),
        .o_rvfi_mode(rvfi_mode),
        .o_rvfi_ixl(rvfi_ixl),
        .o_rvfi_rs1_addr(rvfi_rs1_addr),
        .o_rvfi_rs2_addr(rvfi_rs2_addr),
        .o_rvfi_rs1_rdata(rvfi_rs1_rdata),
        .o_rvfi_rs2_rdata(rvfi_rs2_rdata),
        .o_rvfi_rd_addr(rvfi_rd_addr),
        .o_rvfi_rd_wdata(rvfi_rd_wdata),
        .o_rvfi_pc_rdata(rvfi_pc_rdata),
        .o_rvfi_pc_wdata(rvfi_pc_wdata),
        .o_rvfi_mem_addr(rvfi_mem_addr),
        .o_rvfi_mem_rmask(rvfi_mem_rmask),
        .o_rvfi_mem_wmask(rvfi_mem_wmask),
        .o_rvfi_mem_rdata(rvfi_mem_rdata),
        .o_rvfi_mem_wdata(rvfi_mem_wdata)
    );
`endif
    
    // ==========================================================================
    // STAGE 1: INSTRUCTION FETCH (IF)
    // ==========================================================================
    
    assign if_pc_sequential = if_pc_current +
                              (if_pc_increment_2 ? {{(N-2){1'b0}}, 2'd2}
                                                 : {{(N-3){1'b0}}, 3'd4});
    
    // PC next selection (from EX stage for branches/jumps)
    logic [31:0] branch_or_plus4;
    logic [31:0] normal_pc_next;
    assign branch_or_plus4 = ex_branch_taken ? ex_pc_branch_target : if_pc_sequential;
    
    mux4to1 #(.N(32)) u_if_pc_mux (
        .i_d0(if_pc_sequential),
        .i_d1(branch_or_plus4),
        .i_d2(ex_jump_target),
        .i_d3(ex_jump_target),
        .i_sel(ex_pc_sel),
        .o_y(normal_pc_next)
    );

    assign if_pc_next = system_redirect ? system_redirect_pc : normal_pc_next;
    
    // Program Counter (with stall capability)
    program_counter #(
        .N(N),
        .RESET_VECTOR(RESET_VECTOR)
    ) u_if_pc_reg (
        .i_clk(i_clk),
        .i_arst_n(i_arst_n),
        // A taken branch/jump in EX must win over a CSR interlock caused by a
        // younger, wrong-path CSR instruction in ID.
        .i_pc(pc_hold ? if_pc_current : if_pc_next),
        .o_pc(if_pc_current)
    );
    
    // The external port always performs aligned 32-bit reads.  The fetch
    // buffer selects/decompresses halfwords and assembles a 32-bit instruction
    // that crosses a word boundary.
    rv32c_fetch_buffer #(.N(N)) u_if_fetch_buffer (
        .i_clk(i_clk),
        .i_arst_n(i_arst_n),
        // A redirect can remain asserted while a cross-word fetch stalls the
        // pipeline. Flush only on the cycle that the redirect is actually
        // accepted; otherwise the first halfword would be discarded forever.
        .i_flush(pipeline_flush_if_id && pipeline_advance),
        .i_consume(if_consume),
        .i_pc(if_pc_current),
        .i_response_valid(o_imem_valid && i_imem_ready),
        .i_response_data(i_imem_rdata),
        .i_response_error(i_imem_error === 1'b1),
        .o_request_valid(if_request_valid),
        .o_bus_addr(o_imem_addr),
        .o_complete(if_complete),
        .o_instruction(if_instruction),
        .o_raw_instruction(if_raw_instruction),
        .o_compressed(if_compressed),
        .o_pc_increment_2(if_pc_increment_2),
        .o_access_fault(if_access_fault)
    );

    assign if_consume = if_complete && !stall_if_id && pipeline_advance;

    // A data transfer can finish while the instruction side is still waiting.
    // Remember completion, error and read data until the global pipeline can
    // advance; this also prevents a store from being accepted more than once.
    always_ff @(posedge i_clk or negedge i_arst_n) begin
        if (!i_arst_n) begin
            dmem_complete <= 1'b0;
            dmem_error_pending <= 1'b0;
        end else if (!dmem_request || pipeline_advance) begin
            dmem_complete <= 1'b0;
            dmem_error_pending <= 1'b0;
        end else if (o_dmem_valid && i_dmem_ready) begin
            dmem_complete <= 1'b1;
            dmem_error_pending <= (i_dmem_error === 1'b1);
        end
    end

    // Read data is observable only while dmem_complete is set. Avoid placing
    // this payload register on the asynchronous reset tree.
    always_ff @(posedge i_clk) begin
        if (o_dmem_valid && i_dmem_ready && !pipeline_advance)
            dmem_rdata_latched <= i_dmem_rdata;
    end
    
    // ==========================================================================
    // IF/ID Pipeline Register
    // ==========================================================================
    
    if_id_register #(.N(N)) u_if_id_reg (
        .i_clk(i_clk),
        .i_arst_n(i_arst_n),
        .i_stall(stall_if_id || pipeline_stall),
        .i_flush(pipeline_flush_if_id),
        .i_valid(if_complete),
        .i_access_fault(if_access_fault),
        .i_pc(if_pc_current),
        .i_instruction(if_instruction),
        .i_raw_instruction(if_raw_instruction),
        .i_compressed(if_compressed),
        .o_valid(id_valid),
        .o_access_fault(id_instruction_access_fault),
        .o_pc(id_pc),
        .o_instruction(id_instruction),
        .o_raw_instruction(id_raw_instruction),
        .o_compressed(id_compressed)
    );
    
    // ==========================================================================
    // STAGE 2: INSTRUCTION DECODE (ID)
    // ==========================================================================
    
    // Instruction field extraction
    assign id_rs1_addr = id_instruction[19:15];
    assign id_rs2_addr = id_instruction[24:20];
    assign id_rd_addr  = id_instruction[11:7];
    
    logic id_rs1_read, id_rs2_read;
    
    // Control Unit
    control_unit u_id_control (
        .i_instruction(id_instruction),
        .o_reg_write(id_reg_write),
        .o_mem_read(id_mem_read),
        .o_mem_write(id_mem_write),
        .o_wb_sel(id_wb_sel),
        .o_pc_sel(id_pc_sel),
        .o_alu_src(id_alu_src),
        .o_alu_a_sel(id_alu_a_sel),
        .o_alu_ctrl(id_alu_ctrl),
        .o_branch_en(id_branch_en),
        .o_branch_type(id_branch_type),
        .o_mem_type(id_mem_type),
        .o_jal(id_jal),
        .o_jalr(id_jalr),
        .o_rs1_read(id_rs1_read),
        .o_rs2_read(id_rs2_read),
        .o_csr_en(id_csr_en),
        .o_csr_op(id_csr_op),
        .o_csr_imm(id_csr_imm),
        .o_ecall(id_ecall),
        .o_ebreak(id_ebreak),
        .o_mret(id_mret),
        .o_wfi(id_wfi),
        .o_fence_i(id_fence_i),
        .o_illegal(id_illegal)
    );
    
    // Register File (write happens in WB stage)
    register_file #(
        .N(N),
        .DEPTH(REG_DEPTH)
    ) u_id_regfile (
        .i_clk(i_clk),
        .i_arst_n(i_arst_n),
        .i_write_enable(wb_valid && wb_reg_write),
        .i_rs1_addr(id_rs1_addr),
        .i_rs2_addr(id_rs2_addr),
        .i_rd_addr(wb_rd_addr),
        .i_rd_data(wb_data),
        .o_rs1_data(id_rs1_data),
        .o_rs2_data(id_rs2_data)
    );
    
    // Immediate Generation
    immediate_generator #(.N(N)) u_id_immgen (
        .i_inst(id_instruction),
        .o_imm(id_immediate)
    );
    
    // ==========================================================================
    // Hazard Detection Unit
    // ==========================================================================
    
    hazard_detection_unit u_hazard_unit (
        .i_id_rs1_addr(id_rs1_addr),
        .i_id_rs2_addr(id_rs2_addr),
        .i_id_rs1_read(id_rs1_read),
        .i_id_rs2_read(id_rs2_read),
        .i_id_mem_write(id_mem_write),
        .i_ex_rd_addr(ex_rd_addr),
        .i_ex_mem_read(ex_mem_read),
        .i_ex_reg_write(ex_reg_write),
        .i_ex_branch_taken(ex_branch_taken),
        .i_ex_jal(ex_jal),
        .i_ex_jalr(ex_jalr),
        .o_stall_pc(hazard_stall_pc),
        .o_stall_if_id(hazard_stall_if_id),
        .o_flush_id_ex(hazard_flush_id_ex),
        .o_flush_if_id(hazard_flush_if_id)
    );

    // CSR accesses are architecturally ordered after all older instructions.
    // Drain EX/MEM/WB before allowing a CSR instruction to enter EX so that
    // reads of instret observe every preceding instruction as already retired.
    // This also gives CSR writes strict program order without speculative CSR
    // state or counter-specific forwarding.
    assign csr_order_stall = id_valid && id_csr_en &&
                             (ex_valid || mem_valid || wb_valid);
    assign stall_pc        = hazard_stall_pc || csr_order_stall;
    assign stall_if_id     = hazard_stall_if_id || csr_order_stall;
    assign flush_id_ex     = hazard_flush_id_ex || csr_order_stall;
    assign flush_if_id     = hazard_flush_if_id;

    // System redirects have architectural priority over younger hazard state.
    // ID/EX and later boundaries still hold on pipeline_stall, preserving an
    // older bus transaction until the cycle in which redirect is permitted.
    assign pipeline_flush_if_id = system_redirect || flush_if_id;
    assign pipeline_flush_id_ex = system_redirect || flush_id_ex;
    assign pc_hold = core_sleep || pipeline_stall ||
                     (stall_pc && !system_redirect && !hazard_flush_if_id);
    
    // ==========================================================================
    // ID/EX Pipeline Register
    // ==========================================================================
    
    id_ex_register #(.N(N)) u_id_ex_reg (
        .i_clk(i_clk),
        .i_arst_n(i_arst_n),
        .i_stall(pipeline_stall),
        .i_flush(pipeline_flush_id_ex),
        .i_wb_write(o_commit_rd_write),
        .i_wb_addr(wb_rd_addr),
        .i_wb_data(wb_data),
        .i_valid(id_valid),
        .i_access_fault(id_instruction_access_fault),
        .i_pc(id_pc),
        .i_instruction(id_instruction),
        .i_raw_instruction(id_raw_instruction),
        .i_compressed(id_compressed),
        .i_rs1_data(id_rs1_data),
        .i_rs2_data(id_rs2_data),
        .i_immediate(id_immediate),
        .i_rs1_addr(id_rs1_addr),
        .i_rs2_addr(id_rs2_addr),
        .i_rd_addr(id_rd_addr),
        .i_reg_write(id_reg_write),
        .i_mem_read(id_mem_read),
        .i_mem_write(id_mem_write),
        .i_rs1_read(id_rs1_read),
        .i_rs2_read(id_rs2_read),
        .i_wb_sel(id_wb_sel),
        .i_pc_sel(id_pc_sel),
        .i_alu_src(id_alu_src),
        .i_alu_a_sel(id_alu_a_sel),
        .i_alu_ctrl(id_alu_ctrl),
        .i_branch_en(id_branch_en),
        .i_branch_type(id_branch_type),
        .i_mem_type(id_mem_type),
        .i_jal(id_jal),
        .i_jalr(id_jalr),
        .i_csr_en(id_csr_en),
        .i_csr_op(id_csr_op),
        .i_csr_imm(id_csr_imm),
        .i_ecall(id_ecall),
        .i_ebreak(id_ebreak),
        .i_mret(id_mret),
        .i_wfi(id_wfi),
        .i_fence_i(id_fence_i),
        .i_illegal(id_illegal),
        .o_valid(ex_valid),
        .o_access_fault(ex_instruction_access_fault),
        .o_pc(ex_pc),
        .o_instruction(ex_instruction),
        .o_raw_instruction(ex_raw_instruction),
        .o_compressed(ex_compressed),
        .o_rs1_data(ex_rs1_data),
        .o_rs2_data(ex_rs2_data),
        .o_immediate(ex_immediate),
        .o_rs1_addr(ex_rs1_addr),
        .o_rs2_addr(ex_rs2_addr),
        .o_rd_addr(ex_rd_addr),
        .o_reg_write(ex_reg_write),
        .o_mem_read(ex_mem_read),
        .o_mem_write(ex_mem_write),
        .o_rs1_read(ex_rs1_read),
        .o_rs2_read(ex_rs2_read),
        .o_wb_sel(ex_wb_sel),
        .o_pc_sel(ex_pc_sel),
        .o_alu_src(ex_alu_src),
        .o_alu_a_sel(ex_alu_a_sel),
        .o_alu_ctrl(ex_alu_ctrl),
        .o_branch_en(ex_branch_en),
        .o_branch_type(ex_branch_type),
        .o_mem_type(ex_mem_type),
        .o_jal(ex_jal),
        .o_jalr(ex_jalr),
        .o_csr_en(ex_csr_en),
        .o_csr_op(ex_csr_op),
        .o_csr_imm(ex_csr_imm),
        .o_ecall(ex_ecall),
        .o_ebreak(ex_ebreak),
        .o_mret(ex_mret),
        .o_wfi(ex_wfi),
        .o_fence_i(ex_fence_i),
        .o_illegal(ex_illegal)
    );
    
    // ==========================================================================
    // STAGE 3: EXECUTE (EX)
    // ==========================================================================
    
    // Forwarding Unit
    forwarding_unit u_forward_unit (
        .i_ex_rs1_addr(ex_rs1_addr),
        .i_ex_rs2_addr(ex_rs2_addr),
        .i_mem_rd_addr(mem_rd_addr),
        // A load result is available from the registered WB path after the
        // mandatory load-use bubble.  Do not feed the combinational DMEM
        // response into EX/MEM forwarding; besides being unnecessary, that
        // creates a bus-response -> forwarding -> ALU critical path.
        .i_mem_reg_write(mem_valid && mem_reg_write && !mem_mem_read),
        .i_wb_rd_addr(wb_rd_addr),
        .i_wb_reg_write(wb_valid && wb_reg_write),
        .o_forward_a(forward_a),
        .o_forward_b(forward_b)
    );

    // EX normalizes every non-load writeback source before the EX/MEM
    // boundary. Forwarding therefore has one registered source and no longer
    // places the MEM writeback selector on the branch/redirect critical path.
    assign mem_forward_data = mem_alu_result;
    
    // Forward rs1_data
    mux3to1 #(.N(N)) u_ex_forward_a_mux (
        .i_d0(ex_rs1_data),           // No forwarding
        .i_d1(wb_data),                // Forward from WB
        .i_d2(mem_forward_data),        // Forward architectural MEM result
        .i_sel(forward_a),
        .o_y(ex_alu_operand_a_forwarded)
    );
    
    // Forward rs2_data
    mux3to1 #(.N(N)) u_ex_forward_b_mux (
        .i_d0(ex_rs2_data),           // No forwarding
        .i_d1(wb_data),                // Forward from WB
        .i_d2(mem_forward_data),        // Forward architectural MEM result
        .i_sel(forward_b),
        .o_y(ex_rs2_data_forwarded)
    );
    
    // ALU operand A selection (PC or rs1)
    assign ex_alu_operand_a = ex_alu_a_sel ? ex_pc : ex_alu_operand_a_forwarded;
    
    // ALU operand B selection (immediate or rs2)
    assign ex_alu_operand_b = ex_alu_src ? ex_immediate : ex_rs2_data_forwarded;

    mdu_unit #(.N(N)) u_ex_mdu (
        .i_clk(i_clk),
        .i_arst_n(i_arst_n),
        .i_valid(ex_valid),
        .i_instruction_access_fault(ex_instruction_access_fault),
        .i_funct7(ex_instruction[31:25]),
        .i_funct3(ex_instruction[14:12]),
        .i_opcode(ex_instruction[6:0]),
        .i_operand_a(ex_alu_operand_a),
        .i_operand_b(ex_alu_operand_b),
        .i_result_ready(!bus_stall),
        .o_active(ex_mdu_active),
        .o_stall(mdu_stall),
        .o_result(ex_mdu_result)
    );
    
    // ALU Unit
    alu_unit #(.N(N)) u_ex_alu (
        .i_operand_a(ex_alu_operand_a),
        .i_operand_b(ex_alu_operand_b),
        .i_alu_ctrl(ex_alu_ctrl),
        .o_alu_result(ex_alu_result)
    );
    
    // Shared PC-relative target calculation for branches and JAL.
    adder_n_bit #(.N(N)) u_ex_branch_adder (
        .i_a  (ex_pc),
        .i_b  (ex_immediate),
        .o_sum(ex_pc_branch_target)
    );
    
    // Branch Unit
    branch_unit #(.N(N)) u_ex_branch (
        .i_rs1_data(ex_alu_operand_a_forwarded),
        .i_rs2_data(ex_rs2_data_forwarded),
        .i_branch_type(ex_branch_type),
        .i_branch_en(ex_branch_en),
        .o_branch_taken(ex_branch_taken)
    );
    
    // Jump Unit
    jump_unit #(.N(N)) u_ex_jump (
        .i_pc(ex_pc),
        .i_rs1_data(ex_alu_operand_a_forwarded),
        .i_immediate(ex_immediate),
        .i_pc_relative_target(ex_pc_branch_target),
        .i_jal(ex_jal),
        .i_jalr(ex_jalr),
        .i_compressed(ex_compressed),
        .o_jump_target(ex_jump_target),
        .o_return_addr(ex_return_addr)
    );

    // CSR instructions read the old CSR value into rd and update the CSR in
    // EX. Global pipeline-stall gating prevents a held instruction from writing
    // the CSR more than once.
    assign ex_csr_addr    = ex_instruction[31:20];
    assign ex_csr_operand = ex_csr_imm ? {{(N-5){1'b0}}, ex_instruction[19:15]}
                                       : ex_alu_operand_a_forwarded;

    always_comb begin
        unique case (ex_csr_op)
            2'b00: ex_csr_wdata = ex_csr_operand;
            2'b01: ex_csr_wdata = ex_csr_rdata | ex_csr_operand;
            2'b10: ex_csr_wdata = ex_csr_rdata & ~ex_csr_operand;
            // ex_csr_op=3 is never produced by the CSR decoder.
            /* verilator coverage_off */
            default: ex_csr_wdata = ex_csr_operand;
            /* verilator coverage_on */
        endcase
    end

    assign csr_write_intent = ex_csr_en &&
                              ((ex_csr_op == 2'b00) || (ex_rs1_addr != 5'd0));
    assign csr_access_illegal = ex_valid && ex_csr_en &&
                                (!csr_valid || (csr_write_intent && !csr_writable));
    assign csr_write = ex_valid && csr_write_intent && csr_valid && csr_writable &&
                       pipeline_advance && !ex_instruction_access_fault &&
                       !data_access_exception && !trap_enter;
    // Keep load/store address generation out of the general ALU result mux.
    // A carry-select implementation reduces the forwarding-to-mtval path
    // without making a misalignment trap depend on the shared MDU result bus.
    adder_n_bit #(
        .N(N),
        .USE_CARRY_SELECT(1'b1),
        .BLOCK_WIDTH(8)
    ) u_ex_data_addr_adder (
        .i_a(ex_alu_operand_a_forwarded),
        .i_b(ex_immediate),
        .o_sum(ex_data_addr)
    );
    always_comb begin
        if (ex_mdu_active)
            ex_result = ex_mdu_result;
        else if (ex_csr_en)
            ex_result = ex_csr_rdata;
        else begin
            unique case (ex_wb_sel)
                2'b10:   ex_result = ex_return_addr;
                2'b11:   ex_result = ex_immediate;
                2'b00:   ex_result = (ex_mem_read || ex_mem_write)
                                      ? ex_data_addr : ex_alu_result;
                // Loads carry their address through EX/MEM. Their memory data
                // replaces it immediately before the MEM/WB register.
                2'b01:   ex_result = ex_data_addr;
                /* verilator coverage_off */
                default: ex_result = ex_alu_result;
                /* verilator coverage_on */
            endcase
        end
    end

    assign control_transfer_target = ex_branch_taken ? ex_pc_branch_target
                                                      : ex_jump_target;
    // RV32C makes IALIGN=16: branch/JAL offsets have bit 0 clear and JALR
    // explicitly clears it, so this architectural exception is unreachable.
    /* verilator coverage_off */
    assign instruction_addr_misaligned = ex_valid &&
                                         (ex_branch_taken || ex_jal || ex_jalr) &&
                                         control_transfer_target[0];
    /* verilator coverage_on */

    always_comb begin
        unique case (ex_mem_type)
            3'b001, 3'b101: data_addr_misaligned = ex_data_addr[0];
            3'b010:         data_addr_misaligned = |ex_data_addr[1:0];
            default:        data_addr_misaligned = 1'b0;
        endcase
    end

    assign illegal_exception = ex_valid && (ex_illegal || csr_access_illegal);
    assign instruction_access_exception = ex_valid && ex_instruction_access_fault;
    assign load_misaligned_exception = ex_valid && ex_mem_read && data_addr_misaligned;
    assign store_misaligned_exception = ex_valid && ex_mem_write && data_addr_misaligned;
    assign load_access_exception = mem_valid && mem_mem_read &&
                                   pipeline_advance &&
                                   (dmem_error_pending ||
                                    (o_dmem_valid && i_dmem_ready &&
                                     (i_dmem_error === 1'b1)));
    assign store_access_exception = mem_valid && mem_mem_write &&
                                    pipeline_advance &&
                                    (dmem_error_pending ||
                                     (o_dmem_valid && i_dmem_ready &&
                                      (i_dmem_error === 1'b1)));
    assign data_access_exception = load_access_exception || store_access_exception;
    assign ex_sync_trap = pipeline_advance &&
                       (instruction_access_exception || illegal_exception ||
                        instruction_addr_misaligned ||
                        (ex_valid && ex_ebreak) || load_misaligned_exception ||
                        store_misaligned_exception || (ex_valid && ex_ecall));
    assign irq_take = ex_valid && csr_irq_pending && !data_access_exception &&
                      !ex_sync_trap && pipeline_advance;
    assign trap_enter = data_access_exception || ex_sync_trap || irq_take;
    assign mret_taken = ex_valid && ex_mret && !data_access_exception &&
                        pipeline_advance;
    assign wfi_sleep = ex_valid && ex_wfi && !data_access_exception &&
                       !ex_sync_trap && !irq_take && pipeline_advance &&
                       !csr_wake_pending;
    assign fence_i_taken = ex_valid && ex_fence_i && !data_access_exception &&
                           !ex_sync_trap && !irq_take && pipeline_advance;
    assign system_redirect = trap_enter || mret_taken || wfi_sleep || fence_i_taken;
    assign trap_vector_base = {csr_mtvec[N-1:2], 2'b00};
    assign trap_vector_offset = {trap_cause[N-3:0], 2'b00};
    assign trap_vector_pc = trap_vector_base +
                            ((irq_take && (csr_mtvec[1:0] == 2'b01))
                             ? trap_vector_offset : '0);
    assign system_redirect_pc = trap_enter ? trap_vector_pc :
                                mret_taken ? csr_mepc :
                                ex_pc + (ex_compressed
                                       ? {{(N-2){1'b0}}, 2'd2}
                                       : {{(N-3){1'b0}}, 3'd4});

    always_ff @(posedge i_clk or negedge i_arst_n) begin
        if (!i_arst_n)
            core_sleep <= 1'b0;
        else if (core_sleep && csr_wake_pending)
            core_sleep <= 1'b0;
        else if (wfi_sleep)
            core_sleep <= 1'b1;
    end

    always_comb begin
        trap_cause = {{(N-4){1'b0}}, 4'd11};
        trap_value = '0;
        trap_pc    = ex_pc;
        if (load_access_exception) begin
            trap_pc    = mem_pc;
            trap_cause = {{(N-3){1'b0}}, 3'd5};
            trap_value = mem_alu_result;
        end else if (store_access_exception) begin
            trap_pc    = mem_pc;
            trap_cause = {{(N-3){1'b0}}, 3'd7};
            trap_value = mem_alu_result;
        end else if (irq_take) begin
            trap_cause = csr_irq_cause;
        end else if (instruction_access_exception) begin
            trap_cause = {{(N-1){1'b0}}, 1'b1};
            trap_value = ex_pc;
        end else if (illegal_exception) begin
            trap_cause = {{(N-2){1'b0}}, 2'd2};
            trap_value = ex_raw_instruction;
        /* verilator coverage_off */
        end else if (instruction_addr_misaligned) begin
            trap_cause = '0;
            trap_value = control_transfer_target;
        /* verilator coverage_on */
        end else if (ex_ebreak) begin
            trap_cause = {{(N-2){1'b0}}, 2'd3};
        end else if (load_misaligned_exception) begin
            trap_cause = {{(N-3){1'b0}}, 3'd4};
            trap_value = ex_data_addr;
        end else if (store_misaligned_exception) begin
            trap_cause = {{(N-3){1'b0}}, 3'd6};
            trap_value = ex_data_addr;
        end
    end

    csr_file #(
        .N         (N),
        .MVENDOR_ID(MVENDOR_ID),
        .MARCH_ID  (MARCH_ID),
        .MIMP_ID   (MIMP_ID),
        .HART_ID   (HART_ID),
        .CONFIG_PTR(CONFIG_PTR)
    ) u_machine_csrs (
        .i_clk(i_clk),
        .i_arst_n(i_arst_n),
        .i_csr_addr(ex_csr_addr),
        .o_csr_rdata(ex_csr_rdata),
        .o_csr_valid(csr_valid),
        .o_csr_writable(csr_writable),
        .i_csr_write(csr_write),
        .i_csr_wdata(ex_csr_wdata),
        .i_trap_enter(trap_enter),
        .i_trap_pc(trap_pc),
        .i_trap_cause(trap_cause),
        .i_trap_value(trap_value),
        .i_mret(mret_taken),
        .i_retire(o_commit_valid),
        .i_time(i_time),
        .i_irq_software(i_irq_software),
        .i_irq_timer(i_irq_timer),
        .i_irq_external(i_irq_external),
        .o_mtvec(csr_mtvec),
        .o_mepc(csr_mepc),
        .o_irq_pending(csr_irq_pending),
        .o_wake_pending(csr_wake_pending),
        .o_irq_cause(csr_irq_cause)
    );
    
    // ==========================================================================
    // EX/MEM Pipeline Register
    // ==========================================================================
    
    logic [4:0] mem_rs2_addr;
    
    ex_mem_register #(.N(N)) u_ex_mem_reg (
        .i_clk(i_clk),
        .i_arst_n(i_arst_n),
        .i_stall(pipeline_stall),
        .i_flush(trap_enter),
        .i_wb_write(o_commit_rd_write),
        .i_wb_addr(wb_rd_addr),
        .i_wb_data(wb_data),
        .i_valid(ex_valid),
        .i_pc(ex_pc),
        .i_instruction(ex_raw_instruction),
        .i_alu_result(ex_result),
        .i_rs2_data(ex_rs2_data_forwarded),
        .i_immediate(ex_immediate),
        .i_rs2_addr(ex_rs2_addr),
        .i_rd_addr(ex_rd_addr),
        .i_branch_taken(ex_branch_taken),
        .i_reg_write(ex_reg_write),
        .i_mem_read(ex_mem_read),
        .i_mem_write(ex_mem_write),
        .i_mem_type(ex_mem_type),
        
        // Carry control-flow information into MEM.
        .i_jal(ex_jal),
        .i_jalr(ex_jalr),
        .o_jal(mem_jal),
        .o_jalr(mem_jalr),
        
        .o_valid(mem_valid),
        .o_pc(mem_pc),
        .o_instruction(mem_instruction),
        .o_alu_result(mem_alu_result),
        .o_rs2_data(mem_rs2_data),
        .o_immediate(mem_immediate),
        .o_rs2_addr(mem_rs2_addr),
        .o_rd_addr(mem_rd_addr),
        .o_branch_taken(mem_branch_taken),
        .o_reg_write(mem_reg_write),
        .o_mem_read(mem_mem_read),
        .o_mem_write(mem_mem_write),
        .o_mem_type(mem_mem_type)
    );
    
    // ==========================================================================
    // STAGE 4: MEMORY ACCESS (MEM)
    // ==========================================================================
    
    // Load/Store Unit
    logic [N-1:0] mem_store_data_forwarded;
    assign mem_store_data_forwarded = (wb_valid && wb_reg_write && (wb_rd_addr != 5'd0) && (wb_rd_addr == mem_rs2_addr)) ? wb_data : mem_rs2_data;

    load_store_unit #(.N(N)) u_mem_lsu (
        .i_mem_type(mem_mem_type),
        .i_mem_read(mem_mem_read),
        .i_mem_write(mem_mem_write),
        .i_byte_offset(mem_alu_result[1:0]),
        .i_mem_read_data(dmem_response_rdata),
        .i_store_data(mem_store_data_forwarded),
        .o_load_data(mem_load_data),
        .o_store_data(mem_store_data),
        .o_byte_enable(mem_byte_enable)
    );

    // Every non-load result was normalized in EX. MEM only substitutes the
    // returned load data, reducing this boundary to a single 2:1 mux.
    assign mem_wb_data = mem_mem_read ? mem_load_data : mem_alu_result;
    
    // ==========================================================================
    // MEM/WB Pipeline Register
    // ==========================================================================

    // MEM/WB is an elastic boundary with an always-ready WB consumer. A
    // non-memory packet completes immediately; a memory packet completes only
    // after its response handshake (or from the one-entry response latch).
    // When an unrelated upstream stall keeps EX/MEM in place after transfer,
    // remember that the packet was consumed and inject bubbles until EX/MEM
    // advances. This guarantees exactly-once retirement without placing global
    // bus backpressure on the MEM/WB payload clock enable.
    assign mem_stage_complete = !dmem_request || dmem_complete ||
                                (o_dmem_valid && i_dmem_ready);
    assign mem_access_error = dmem_error_pending ||
                              (o_dmem_valid && i_dmem_ready &&
                               (i_dmem_error === 1'b1));

    always_ff @(posedge i_clk or negedge i_arst_n) begin
        if (!i_arst_n)
            mem_wb_consumed_q <= 1'b0;
        else if (pipeline_advance)
            mem_wb_consumed_q <= 1'b0;
        else if (mem_wb_fire)
            mem_wb_consumed_q <= 1'b1;
    end

    assign mem_wb_fire = mem_valid && mem_stage_complete &&
                         !mem_access_error && !data_access_exception &&
                         !mem_wb_consumed_q;
    
    mem_wb_register #(.N(N)) u_mem_wb_reg (
        .i_clk(i_clk),
        .i_arst_n(i_arst_n),
        .i_stall(1'b0),
        .i_valid(mem_wb_fire),
        .i_pc(mem_pc),
        .i_instruction(mem_instruction),
        .i_alu_result(mem_alu_result),
        .i_wb_data(mem_wb_data),
        .i_immediate(mem_immediate),
        .i_rd_addr(mem_rd_addr),
        .i_reg_write(mem_reg_write),
        .i_mem_write(mem_mem_write),
        .i_mem_addr(mem_alu_result),
        .i_mem_wdata(mem_store_data),
        .i_mem_wstrb(mem_byte_enable),
        
        // Carry retired control-flow information into WB.
        .i_jal(mem_jal),
        .i_jalr(mem_jalr),
        .i_branch_taken(mem_branch_taken),
        
        .o_valid(wb_valid),
        .o_pc(wb_pc),
        .o_instruction(wb_instruction),
        .o_jal(wb_jal),
        .o_jalr(wb_jalr),
        .o_branch_taken(wb_branch_taken),
        
        .o_alu_result(wb_alu_result),
        .o_wb_data(wb_data),
        .o_immediate(wb_immediate),
        .o_rd_addr(wb_rd_addr),
        .o_reg_write(wb_reg_write),
        .o_mem_write(wb_mem_write),
        .o_mem_addr(wb_mem_addr),
        .o_mem_wdata(wb_mem_wdata),
        .o_mem_wstrb(wb_mem_wstrb)
    );
    
    // ==========================================================================
    // STAGE 5: WRITE BACK (WB)
    // ==========================================================================
    // wb_data is already selected and registered at the MEM/WB boundary.

endmodule
