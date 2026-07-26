// =============================================================================
// ID/EX Pipeline Register
// =============================================================================
// Stores data between Instruction Decode (ID) and Execute (EX) stages
// Includes all control signals, register data, immediate, and PC
// =============================================================================

module id_ex_register #(
    parameter N = 32
)(
    input  logic             i_clk,
    input  logic             i_arst_n,
    input  logic             i_stall,      // Hold state during any global stall
    input  logic             i_flush,      // Flush signal for branch/jump

    // WB repair port. An elastic WB stage may retire while this packet is
    // stalled, so refresh any captured source operand that it produces.
    input  logic             i_wb_write,
    input  logic [4:0]       i_wb_addr,
    input  logic [N-1:0]     i_wb_data,
    
    // Inputs from ID stage
    input  logic             i_valid,
    input  logic             i_access_fault,
    input  logic [N-1:0]     i_pc,
    input  logic [N-1:0]     i_instruction,
    input  logic [N-1:0]     i_raw_instruction,
    input  logic             i_compressed,
    input  logic [N-1:0]     i_rs1_data,
    input  logic [N-1:0]     i_rs2_data,
    input  logic [N-1:0]     i_immediate,
    input  logic [4:0]       i_rs1_addr,
    input  logic [4:0]       i_rs2_addr,
    input  logic [4:0]       i_rd_addr,
    
    // Control signals from ID stage
    input  logic             i_reg_write,
    input  logic             i_mem_read,
    input  logic             i_mem_write,
    input  logic             i_rs1_read,
    input  logic             i_rs2_read,
    input  logic [1:0]       i_wb_sel,
    input  logic [1:0]       i_pc_sel,
    input  logic             i_alu_src,
    input  logic             i_alu_a_sel,
    input  logic [3:0]       i_alu_ctrl,
    input  logic             i_branch_en,
    input  logic [2:0]       i_branch_type,
    input  logic [2:0]       i_mem_type,
    input  logic             i_jal,
    input  logic             i_jalr,
    input  logic             i_csr_en,
    input  logic [1:0]       i_csr_op,
    input  logic             i_csr_imm,
    input  logic             i_ecall,
    input  logic             i_ebreak,
    input  logic             i_mret,
    input  logic             i_wfi,
    input  logic             i_fence_i,
    input  logic             i_illegal,
    
    // Outputs to EX stage
    output logic             o_valid,
    output logic             o_access_fault,
    output logic [N-1:0]     o_pc,
    output logic [N-1:0]     o_instruction,
    output logic [N-1:0]     o_raw_instruction,
    output logic             o_compressed,
    output logic [N-1:0]     o_rs1_data,
    output logic [N-1:0]     o_rs2_data,
    output logic [N-1:0]     o_immediate,
    output logic [4:0]       o_rs1_addr,
    output logic [4:0]       o_rs2_addr,
    output logic [4:0]       o_rd_addr,
    
    // Control signals to EX stage
    output logic             o_reg_write,
    output logic             o_mem_read,
    output logic             o_mem_write,
    output logic             o_rs1_read,
    output logic             o_rs2_read,
    output logic [1:0]       o_wb_sel,
    output logic [1:0]       o_pc_sel,
    output logic             o_alu_src,
    output logic             o_alu_a_sel,
    output logic [3:0]       o_alu_ctrl,
    output logic             o_branch_en,
    output logic [2:0]       o_branch_type,
    output logic [2:0]       o_mem_type,
    output logic             o_jal,
    output logic             o_jalr,
    output logic             o_csr_en,
    output logic [1:0]       o_csr_op,
    output logic             o_csr_imm,
    output logic             o_ecall,
    output logic             o_ebreak,
    output logic             o_mret,
    output logic             o_wfi,
    output logic             o_fence_i,
    output logic             o_illegal
);

    // Keep all execute, exception, and architectural side-effect controls
    // resettable.  Clearing this bank makes the unreset payload below
    // unobservable after reset or a pipeline flush.
    always_ff @(posedge i_clk or negedge i_arst_n) begin
        if (!i_arst_n) begin
            o_valid        <= 1'b0;
            o_access_fault <= 1'b0;
            o_compressed   <= 1'b0;
            o_reg_write    <= 1'b0;
            o_mem_read     <= 1'b0;
            o_mem_write    <= 1'b0;
            o_rs1_read     <= 1'b0;
            o_rs2_read     <= 1'b0;
            o_wb_sel       <= 2'b0;
            o_pc_sel       <= 2'b0;
            o_alu_src      <= 1'b0;
            o_alu_a_sel    <= 1'b0;
            o_alu_ctrl     <= 4'h0;
            o_branch_en    <= 1'b0;
            o_branch_type  <= 3'b0;
            o_mem_type     <= 3'b0;
            o_jal          <= 1'b0;
            o_jalr         <= 1'b0;
            o_csr_en       <= 1'b0;
            o_csr_op       <= 2'b0;
            o_csr_imm      <= 1'b0;
            o_ecall        <= 1'b0;
            o_ebreak       <= 1'b0;
            o_mret         <= 1'b0;
            o_wfi          <= 1'b0;
            o_fence_i      <= 1'b0;
            o_illegal      <= 1'b0;
        end else if (i_stall) begin
            // Keep all outputs stable until the global pipeline can advance.
        end else if (i_flush) begin
            o_valid        <= 1'b0;
            o_access_fault <= 1'b0;
            o_compressed   <= 1'b0;
            o_reg_write    <= 1'b0;
            o_mem_read     <= 1'b0;
            o_mem_write    <= 1'b0;
            o_rs1_read     <= 1'b0;
            o_rs2_read     <= 1'b0;
            o_wb_sel       <= 2'b0;
            o_pc_sel       <= 2'b0;
            o_alu_src      <= 1'b0;
            o_alu_a_sel    <= 1'b0;
            o_alu_ctrl     <= 4'h0;
            o_branch_en    <= 1'b0;
            o_branch_type  <= 3'b0;
            o_mem_type     <= 3'b0;
            o_jal          <= 1'b0;
            o_jalr         <= 1'b0;
            o_csr_en       <= 1'b0;
            o_csr_op       <= 2'b0;
            o_csr_imm      <= 1'b0;
            o_ecall        <= 1'b0;
            o_ebreak       <= 1'b0;
            o_mret         <= 1'b0;
            o_wfi          <= 1'b0;
            o_fence_i      <= 1'b0;
            o_illegal      <= 1'b0;
        end else begin
            o_valid        <= i_valid;
            o_access_fault <= i_access_fault;
            o_compressed   <= i_compressed;
            o_reg_write    <= i_reg_write;
            o_mem_read     <= i_mem_read;
            o_mem_write    <= i_mem_write;
            o_rs1_read     <= i_rs1_read;
            o_rs2_read     <= i_rs2_read;
            o_wb_sel       <= i_wb_sel;
            o_pc_sel       <= i_pc_sel;
            o_alu_src      <= i_alu_src;
            o_alu_a_sel    <= i_alu_a_sel;
            o_alu_ctrl     <= i_alu_ctrl;
            o_branch_en    <= i_branch_en;
            o_branch_type  <= i_branch_type;
            o_mem_type     <= i_mem_type;
            o_jal          <= i_jal;
            o_jalr         <= i_jalr;
            o_csr_en       <= i_csr_en;
            o_csr_op       <= i_csr_op;
            o_csr_imm      <= i_csr_imm;
            o_ecall        <= i_ecall;
            o_ebreak       <= i_ebreak;
            o_mret         <= i_mret;
            o_wfi          <= i_wfi;
            o_fence_i      <= i_fence_i;
            o_illegal      <= i_illegal;
        end
    end

    // Data and register addresses are consumed only under the control bank
    // above.  Do not reset them so synthesis can use non-resettable flops.
    // Capturing them during a flush is harmless because o_valid and every
    // side-effect control are cleared on that same edge.
    always_ff @(posedge i_clk) begin
        if (i_stall) begin
            if (i_wb_write && o_rs1_read && (o_rs1_addr == i_wb_addr))
                o_rs1_data <= i_wb_data;
            if (i_wb_write && o_rs2_read && (o_rs2_addr == i_wb_addr))
                o_rs2_data <= i_wb_data;
        end else begin
            o_pc          <= i_pc;
            o_instruction <= i_instruction;
            o_raw_instruction <= i_raw_instruction;
            o_rs1_data    <= i_rs1_data;
            o_rs2_data    <= i_rs2_data;
            o_immediate   <= i_immediate;
            o_rs1_addr    <= i_rs1_addr;
            o_rs2_addr    <= i_rs2_addr;
            o_rd_addr     <= i_rd_addr;
        end
    end

endmodule
