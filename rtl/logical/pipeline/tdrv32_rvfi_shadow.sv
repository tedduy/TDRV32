// RVFI shadow path for riscv-formal verification.
//
// This module is instantiated only under `RISCV_FORMAL` and mirrors
// architectural retirement metadata that the optimized pipeline does not
// retain.  It is purely observational and never affects architectural
// timing, area or behavior.
module tdrv32_rvfi_shadow #(
    parameter N = 32
)(
    input  logic         i_clk,
    input  logic         i_arst_n,

    // Pipeline global control
    input  logic         i_pipeline_stall,
    input  logic         i_mem_wb_advance,
    input  logic         i_mem_wb_fire,

    // Trap / exception events from the pipeline
    input  logic         i_trap_enter,
    input  logic         i_ex_sync_trap,
    input  logic         i_data_access_exception,

    // EX stage observability
    input  logic         i_ex_valid,
    input  logic [N-1:0] i_ex_pc,
    input  logic         i_ex_compressed,
    input  logic [N-1:0] i_ex_raw_instruction,
    input  logic [4:0]   i_ex_rs1_addr,
    input  logic [4:0]   i_ex_rs2_addr,
    input  logic         i_ex_rs1_read,
    input  logic         i_ex_rs2_read,
    input  logic [N-1:0] i_ex_alu_operand_a_forwarded,
    input  logic [N-1:0] i_ex_rs2_data_forwarded,
    input  logic [N-1:0] i_ex_data_addr,
    input  logic         i_ex_branch_taken,
    input  logic         i_ex_jal,
    input  logic         i_ex_jalr,
    input  logic         i_ex_mret,
    input  logic [N-1:0] i_control_transfer_target,
    input  logic [N-1:0] i_csr_mepc,

    // MEM stage observability
    input  logic [N-1:0] i_mem_pc,
    input  logic [N-1:0] i_mem_instruction,
    input  logic [N-1:0] i_mem_alu_result,
    input  logic         i_mem_mem_read,
    input  logic         i_mem_mem_write,
    input  logic [2:0]   i_mem_mem_type,
    input  logic [N-1:0] i_mem_store_operand,
    input  logic [N-1:0] i_dmem_response_rdata,

    // WB / commit observability
    input  logic         i_commit_valid,
    input  logic         i_commit_rd_write,
    input  logic [N-1:0] i_wb_instruction,
    input  logic [N-1:0] i_wb_pc,
    input  logic [4:0]   i_wb_rd_addr,
    input  logic [N-1:0] i_wb_data,
    input  logic         i_wb_mem_write,
    input  logic [N-1:0] i_wb_mem_addr,
    input  logic [N-1:0] i_wb_mem_wdata,
    input  logic [3:0]   i_wb_mem_wstrb,

    // RISC-V Formal Interface outputs
    output logic         o_rvfi_valid,
    output logic [63:0]  o_rvfi_order,
    output logic [N-1:0] o_rvfi_insn,
    output logic         o_rvfi_trap,
    output logic         o_rvfi_halt,
    output logic         o_rvfi_intr,
    output logic [1:0]   o_rvfi_mode,
    output logic [1:0]   o_rvfi_ixl,
    output logic [4:0]   o_rvfi_rs1_addr,
    output logic [4:0]   o_rvfi_rs2_addr,
    output logic [N-1:0] o_rvfi_rs1_rdata,
    output logic [N-1:0] o_rvfi_rs2_rdata,
    output logic [4:0]   o_rvfi_rd_addr,
    output logic [N-1:0] o_rvfi_rd_wdata,
    output logic [N-1:0] o_rvfi_pc_rdata,
    output logic [N-1:0] o_rvfi_pc_wdata,
    output logic [N-1:0] o_rvfi_mem_addr,
    output logic [3:0]   o_rvfi_mem_rmask,
    output logic [3:0]   o_rvfi_mem_wmask,
    output logic [N-1:0] o_rvfi_mem_rdata,
    output logic [N-1:0] o_rvfi_mem_wdata
);

    logic pipeline_advance;
    assign pipeline_advance = !i_pipeline_stall;

    // =========================================================================
    // Internal state
    // =========================================================================
    logic [63:0]  rvfi_order_q;
    logic         rvfi_have_previous;
    logic [N-1:0] rvfi_expected_pc;
    logic         rvfi_commit_valid;
    logic         rvfi_trap_event, rvfi_trap_pending;
    logic [N-1:0] rvfi_trap_insn_q;
    logic [N-1:0] rvfi_trap_pc_q, rvfi_trap_pc_wdata_q;
    logic [4:0]   rvfi_trap_rs1_addr_q, rvfi_trap_rs2_addr_q;
    logic [N-1:0] rvfi_trap_rs1_rdata_q, rvfi_trap_rs2_rdata_q;
    logic [N-1:0] rvfi_trap_mem_addr_q, rvfi_trap_mem_rdata_q;
    logic [3:0]   rvfi_trap_mem_rmask_q;
    logic         rvfi_mem_valid_shadow, rvfi_wb_valid_shadow;
    logic [4:0]   rvfi_mem_rs1_addr, rvfi_mem_rs2_addr;
    logic [4:0]   rvfi_wb_rs1_addr, rvfi_wb_rs2_addr;
    logic [N-1:0] rvfi_mem_rs1_rdata, rvfi_mem_rs2_rdata;
    logic [N-1:0] rvfi_wb_rs1_rdata, rvfi_wb_rs2_rdata;
    logic [N-1:0] rvfi_mem_pc_wdata, rvfi_wb_pc_wdata;
    logic [3:0]   rvfi_wb_mem_rmask;
    logic [N-1:0] rvfi_wb_mem_rdata;
    logic [N-1:0] rvfi_ex_pc_wdata;
    logic [3:0]   rvfi_mem_read_mask;
    logic [N-1:0] rvfi_rs1_observed, rvfi_rs2_observed;
`ifdef TDRV32_FORMAL_REG_HISTORY
    logic [4:0]   rvfi_write_addr_history [0:7];
    logic [N-1:0] rvfi_write_data_history [0:7];
    logic [7:0]   rvfi_write_valid_history;
    integer       rvfi_history_shift_index;
    integer       rvfi_history_lookup_index;
`endif

    // =========================================================================
    // Architectural next PC for the instruction currently in EX.
    // =========================================================================
    always_comb begin
        rvfi_ex_pc_wdata = i_ex_pc + (i_ex_compressed
                                    ? {{(N-2){1'b0}}, 2'd2}
                                    : {{(N-3){1'b0}}, 3'd4});
        if (i_ex_branch_taken || i_ex_jal || i_ex_jalr)
            rvfi_ex_pc_wdata = i_control_transfer_target;
        if (i_ex_mret)
            rvfi_ex_pc_wdata = i_csr_mepc;
    end

    // =========================================================================
    // Memory read mask (RISCV_FORMAL_ALIGNED_MEM)
    // =========================================================================
    // The native bus is 32 bits wide. Report aligned memory words and identify
    // valid load bytes with the mask required by RISCV_FORMAL_ALIGNED_MEM.
    always_comb begin
        rvfi_mem_read_mask = 4'b0000;
        if (i_mem_mem_read) begin
            unique case (i_mem_mem_type)
                3'b000, 3'b100:
                    rvfi_mem_read_mask = 4'b0001 << i_mem_alu_result[1:0];
                3'b001, 3'b101:
                    rvfi_mem_read_mask = 4'b0011 << {i_mem_alu_result[1], 1'b0};
                3'b010:
                    rvfi_mem_read_mask = 4'b1111;
                default:
                    rvfi_mem_read_mask = 4'b0000;
            endcase
        end
    end

    // =========================================================================
    // Shadow valid and trap tracking
    // =========================================================================
    // Mirror only metadata that the optimized architectural pipeline does not
    // retain. The shadow valids follow the same hold/flush rules as EX/MEM and
    // MEM/WB, keeping each packet aligned with i_commit_valid.
    always_ff @(posedge i_clk or negedge i_arst_n) begin
        if (!i_arst_n) begin
            rvfi_mem_valid_shadow <= 1'b0;
            rvfi_wb_valid_shadow  <= 1'b0;
            rvfi_order_q          <= 64'b0;
            rvfi_have_previous    <= 1'b0;
            rvfi_trap_pending     <= 1'b0;
`ifdef TDRV32_FORMAL_REG_HISTORY
            rvfi_write_valid_history <= '0;
`endif
        end else begin
`ifdef TDRV32_FORMAL_REG_HISTORY
            if (o_rvfi_valid && !o_rvfi_trap &&
                (o_rvfi_rd_addr != 5'd0)) begin
                for (rvfi_history_shift_index = 7;
                     rvfi_history_shift_index > 0;
                     rvfi_history_shift_index =
                         rvfi_history_shift_index - 1) begin
                    rvfi_write_addr_history[rvfi_history_shift_index] <=
                        rvfi_write_addr_history[rvfi_history_shift_index - 1];
                    rvfi_write_data_history[rvfi_history_shift_index] <=
                        rvfi_write_data_history[rvfi_history_shift_index - 1];
                    rvfi_write_valid_history[rvfi_history_shift_index] <=
                        rvfi_write_valid_history[
                            rvfi_history_shift_index - 1];
                end
                rvfi_write_addr_history[0] <= o_rvfi_rd_addr;
                rvfi_write_data_history[0] <= o_rvfi_rd_wdata;
                rvfi_write_valid_history[0] <= 1'b1;
            end
`endif

            if (o_rvfi_valid) begin
                rvfi_order_q <= rvfi_order_q + 64'd1;
                rvfi_have_previous <= 1'b1;
                rvfi_expected_pc <= o_rvfi_pc_wdata;
            end

            if (rvfi_trap_event)
                rvfi_trap_pending <= 1'b1;
            else if (rvfi_trap_pending && !rvfi_commit_valid)
                rvfi_trap_pending <= 1'b0;

            if (rvfi_trap_event) begin
                if (i_data_access_exception) begin
                    rvfi_trap_insn_q       <= i_mem_instruction;
                    rvfi_trap_pc_q         <= i_mem_pc;
                    rvfi_trap_pc_wdata_q   <= i_mem_pc +
                        ((i_mem_instruction[1:0] == 2'b11) ? 32'd4 : 32'd2);
                    rvfi_trap_rs1_addr_q   <= rvfi_mem_rs1_addr;
                    rvfi_trap_rs2_addr_q   <= rvfi_mem_rs2_addr;
                    rvfi_trap_rs1_rdata_q  <= rvfi_mem_rs1_rdata;
                    rvfi_trap_rs2_rdata_q  <= i_mem_mem_write
                                            ? i_mem_store_operand
                                            : rvfi_mem_rs2_rdata;
                    rvfi_trap_mem_addr_q   <= {i_mem_alu_result[N-1:2], 2'b00};
                    rvfi_trap_mem_rdata_q  <= i_dmem_response_rdata;
                    rvfi_trap_mem_rmask_q  <= rvfi_mem_read_mask;
                end else begin
                    rvfi_trap_insn_q       <= i_ex_raw_instruction;
                    rvfi_trap_pc_q         <= i_ex_pc;
                    rvfi_trap_pc_wdata_q   <= i_ex_pc +
                        (i_ex_compressed ? 32'd2 : 32'd4);
                    rvfi_trap_rs1_addr_q   <= i_ex_rs1_read
                                            ? i_ex_rs1_addr : 5'd0;
                    rvfi_trap_rs2_addr_q   <= i_ex_rs2_read
                                            ? i_ex_rs2_addr : 5'd0;
                    rvfi_trap_rs1_rdata_q  <= i_ex_rs1_read
                                            ? i_ex_alu_operand_a_forwarded : '0;
                    rvfi_trap_rs2_rdata_q  <= i_ex_rs2_read
                                            ? i_ex_rs2_data_forwarded : '0;
                    rvfi_trap_mem_addr_q   <= {i_ex_data_addr[N-1:2], 2'b00};
                    rvfi_trap_mem_rdata_q  <= '0;
                    rvfi_trap_mem_rmask_q  <= 4'b0000;
                end
            end

            if (!i_pipeline_stall)
                rvfi_mem_valid_shadow <= i_ex_valid && !i_trap_enter;

            if (i_mem_wb_advance)
                rvfi_wb_valid_shadow <= i_mem_wb_fire;
        end
    end

    // =========================================================================
    // Operand / PC shadow pipeline
    // =========================================================================
    always_ff @(posedge i_clk) begin
        if (!i_pipeline_stall) begin
            rvfi_mem_rs1_addr  <= i_ex_rs1_read ? i_ex_rs1_addr : 5'd0;
            rvfi_mem_rs2_addr  <= i_ex_rs2_read ? i_ex_rs2_addr : 5'd0;
            rvfi_mem_rs1_rdata <= i_ex_rs1_read
                                ? i_ex_alu_operand_a_forwarded : '0;
            rvfi_mem_rs2_rdata <= i_ex_rs2_read
                                ? i_ex_rs2_data_forwarded : '0;
            rvfi_mem_pc_wdata  <= rvfi_ex_pc_wdata;
        end

        if (i_mem_wb_advance) begin
            rvfi_wb_rs1_addr   <= rvfi_mem_rs1_addr;
            rvfi_wb_rs2_addr   <= rvfi_mem_rs2_addr;
            rvfi_wb_rs1_rdata  <= rvfi_mem_rs1_rdata;
            // Store data can receive a late WB-to-MEM forwarding update after
            // EX. Report the value actually consumed by the memory operation.
            rvfi_wb_rs2_rdata  <= i_mem_mem_write
                                ? i_mem_store_operand : rvfi_mem_rs2_rdata;
            rvfi_wb_pc_wdata   <= rvfi_mem_pc_wdata;
            rvfi_wb_mem_rmask  <= rvfi_mem_read_mask;
            rvfi_wb_mem_rdata  <= i_dmem_response_rdata;
        end
    end

    // =========================================================================
    // Output assignments
    // =========================================================================
    assign rvfi_commit_valid = i_commit_valid && rvfi_wb_valid_shadow;
    assign rvfi_trap_event = i_ex_sync_trap || i_data_access_exception;
    assign o_rvfi_valid     = rvfi_commit_valid || rvfi_trap_pending;
    assign o_rvfi_order     = rvfi_order_q;
    assign o_rvfi_insn      = rvfi_commit_valid ? i_wb_instruction
                                               : rvfi_trap_insn_q;
    assign o_rvfi_trap      = !rvfi_commit_valid && rvfi_trap_pending;
    assign o_rvfi_halt      = 1'b0;
    assign o_rvfi_intr      = o_rvfi_valid && rvfi_have_previous &&
                            (o_rvfi_pc_rdata != rvfi_expected_pc);
    assign o_rvfi_mode      = 2'b11;
    assign o_rvfi_ixl       = 2'b01;
    assign o_rvfi_rs1_addr  = rvfi_commit_valid ? rvfi_wb_rs1_addr
                                               : rvfi_trap_rs1_addr_q;
    assign o_rvfi_rs2_addr  = rvfi_commit_valid ? rvfi_wb_rs2_addr
                                               : rvfi_trap_rs2_addr_q;
    always_comb begin
        rvfi_rs1_observed = rvfi_commit_valid ? rvfi_wb_rs1_rdata
                                              : rvfi_trap_rs1_rdata_q;
        rvfi_rs2_observed = rvfi_commit_valid ? rvfi_wb_rs2_rdata
                                              : rvfi_trap_rs2_rdata_q;
`ifdef TDRV32_FORMAL_REG_HISTORY
        // Eight entries cover every earlier retirement visible at the
        // configured 12-cycle register proof without burdening ISA checks.
        for (rvfi_history_lookup_index = 7;
             rvfi_history_lookup_index >= 0;
             rvfi_history_lookup_index =
                 rvfi_history_lookup_index - 1) begin
            if (rvfi_write_valid_history[rvfi_history_lookup_index] &&
                (rvfi_write_addr_history[rvfi_history_lookup_index] ==
                 o_rvfi_rs1_addr))
                rvfi_rs1_observed =
                    rvfi_write_data_history[rvfi_history_lookup_index];
            if (rvfi_write_valid_history[rvfi_history_lookup_index] &&
                (rvfi_write_addr_history[rvfi_history_lookup_index] ==
                 o_rvfi_rs2_addr))
                rvfi_rs2_observed =
                    rvfi_write_data_history[rvfi_history_lookup_index];
        end
`endif
    end

    assign o_rvfi_rs1_rdata = (o_rvfi_rs1_addr == 5'd0)
                            ? '0 : rvfi_rs1_observed;
    assign o_rvfi_rs2_rdata = (o_rvfi_rs2_addr == 5'd0)
                            ? '0 : rvfi_rs2_observed;
    assign o_rvfi_rd_addr   = rvfi_commit_valid && i_commit_rd_write
                            ? i_wb_rd_addr : 5'd0;
    assign o_rvfi_rd_wdata  = rvfi_commit_valid && i_commit_rd_write
                            ? i_wb_data : '0;
    assign o_rvfi_pc_rdata  = rvfi_commit_valid ? i_wb_pc : rvfi_trap_pc_q;
    assign o_rvfi_pc_wdata  = rvfi_commit_valid ? rvfi_wb_pc_wdata
                                               : rvfi_trap_pc_wdata_q;
    assign o_rvfi_mem_addr  = rvfi_commit_valid
                            ? {i_wb_mem_addr[N-1:2], 2'b00}
                            : rvfi_trap_mem_addr_q;
    assign o_rvfi_mem_rmask = rvfi_commit_valid ? rvfi_wb_mem_rmask
                                               : rvfi_trap_mem_rmask_q;
    assign o_rvfi_mem_wmask = rvfi_commit_valid && i_wb_mem_write
                            ? i_wb_mem_wstrb : 4'b0000;
    assign o_rvfi_mem_rdata = rvfi_commit_valid ? rvfi_wb_mem_rdata
                                               : rvfi_trap_mem_rdata_q;
    assign o_rvfi_mem_wdata = rvfi_commit_valid ? i_wb_mem_wdata : '0;

endmodule
