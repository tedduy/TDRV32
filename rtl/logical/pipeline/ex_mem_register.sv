// =============================================================================
// EX/MEM Pipeline Register
// =============================================================================
// Stores data between Execute (EX) and Memory (MEM) stages
// =============================================================================

module ex_mem_register #(
    parameter N = 32
)(
    input  logic             i_clk,
    input  logic             i_arst_n,
    input  logic             i_stall,
    input  logic             i_flush,

    // Preserve late store-data forwarding when elastic WB retires while this
    // MEM packet is held by external backpressure.
    input  logic             i_wb_write,
    input  logic [4:0]       i_wb_addr,
    input  logic [N-1:0]     i_wb_data,
    
    // Inputs from EX stage
    input  logic             i_valid,
    input  logic [N-1:0]     i_pc,
    input  logic [N-1:0]     i_instruction,
    input  logic [N-1:0]     i_alu_result,
    input  logic [N-1:0]     i_rs2_data,
    input  logic [N-1:0]     i_immediate,
    input  logic [4:0]       i_rs2_addr,
    input  logic [4:0]       i_rd_addr,
    input  logic             i_branch_taken,
    
    // Control signals from EX stage
    input  logic             i_reg_write,
    input  logic             i_mem_read,
    input  logic             i_mem_write,
    input  logic [2:0]       i_mem_type,
    
    // Jump controls from EX
    input  logic             i_jal, 
    input  logic             i_jalr,
    
    // Outputs to MEM stage
    output logic             o_valid,
    output logic [N-1:0]     o_pc,
    output logic [N-1:0]     o_instruction,
    output logic [N-1:0]     o_alu_result,
    output logic [N-1:0]     o_rs2_data,
    output logic [N-1:0]     o_immediate,
    output logic [4:0]       o_rs2_addr,
    output logic [4:0]       o_rd_addr,
    output logic             o_branch_taken,
    
    // Control signals to MEM stage
    output logic             o_reg_write,
    output logic             o_mem_read,
    output logic             o_mem_write,
    output logic [2:0]       o_mem_type,
    
    // Jump controls to MEM
    output logic             o_jal,
    output logic             o_jalr
);

    // Keep only architectural control state resettable.  These benign values
    // prevent uninitialized payload data from issuing a memory transaction,
    // forwarding a result, or writing the register file after reset/flush.
    always_ff @(posedge i_clk or negedge i_arst_n) begin
        if (!i_arst_n) begin
            o_valid            <= 1'b0;
            o_branch_taken     <= 1'b0;
            o_reg_write        <= 1'b0;
            o_mem_read         <= 1'b0;
            o_mem_write        <= 1'b0;
            o_mem_type         <= 3'b0;
            o_jal              <= 1'b0;
            o_jalr             <= 1'b0;
        end else if (i_stall) begin
            // Keep the stage and any memory request stable during a global stall.
        end else if (i_flush) begin
            o_valid            <= 1'b0;
            o_branch_taken     <= 1'b0;
            o_reg_write        <= 1'b0;
            o_mem_read         <= 1'b0;
            o_mem_write        <= 1'b0;
            o_mem_type         <= 3'b0;
            o_jal              <= 1'b0;
            o_jalr             <= 1'b0;
        end else begin
            o_valid            <= i_valid;
            o_branch_taken     <= i_branch_taken;
            o_reg_write        <= i_reg_write;
            o_mem_read         <= i_mem_read;
            o_mem_write        <= i_mem_write;
            o_mem_type         <= i_mem_type;
            o_jal              <= i_jal;
            o_jalr             <= i_jalr;
        end
    end

    // Payload is meaningful only when o_valid or its associated control is
    // asserted.  Leaving it unreset lets synthesis select smaller flops.  A
    // flush invalidates the control bank, so capturing payload on that cycle
    // is harmless and avoids adding flush to every payload clock enable.
    always_ff @(posedge i_clk) begin
        if (i_stall) begin
            if (i_wb_write && o_mem_write && (o_rs2_addr == i_wb_addr))
                o_rs2_data <= i_wb_data;
        end else begin
            o_pc               <= i_pc;
            o_instruction      <= i_instruction;
            o_alu_result       <= i_alu_result;
            o_rs2_data         <= i_rs2_data;
            o_rs2_addr         <= i_rs2_addr;
            o_immediate        <= i_immediate;
            o_rd_addr          <= i_rd_addr;
        end
    end

endmodule
