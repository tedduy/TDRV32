// Converts an aligned 32-bit instruction-memory response stream into one
// canonical RV32 instruction at the requested halfword-aligned PC. A 32-bit
// instruction beginning in the upper half of a bus word is assembled using a
// second aligned read. A one-entry response hold prevents duplicate bus
// transactions when the downstream pipeline cannot consume a response.
module rv32c_fetch_buffer #(
    parameter N = 32
)(
    input  logic         i_clk,
    input  logic         i_arst_n,
    input  logic         i_flush,
    input  logic         i_consume,
    input  logic [N-1:0] i_pc,

    input  logic         i_response_valid,
    input  logic [31:0]  i_response_data,
    input  logic         i_response_error,

    output logic         o_request_valid,
    output logic [N-1:0] o_bus_addr,
    output logic         o_complete,
    output logic [31:0]  o_instruction,
    output logic [31:0]  o_raw_instruction,
    output logic         o_compressed,
    output logic         o_pc_increment_2,
    output logic         o_access_fault
);

    logic        cross_pending_q;
    logic [15:0] first_half_q;
    logic        response_held_q;
    logic        held_cross_q;
    logic        held_error_q;
    logic [31:0] held_response_q;
    logic [31:0] active_response;
    logic [15:0] compressed_parcel;
    logic [31:0] decompressed_instruction;
    logic        decompressed_illegal;
    logic        starts_cross_word;
    (* keep = "true" *) logic pc_increment_2_fast;

    assign o_request_valid = !response_held_q;
    assign o_bus_addr = cross_pending_q
                      ? {i_pc[N-1:2], 2'b00} + {{(N-3){1'b0}}, 3'd4}
                      : {i_pc[N-1:2], 2'b00};

    assign active_response = response_held_q ? held_response_q
                                              : i_response_data;
    assign compressed_parcel = i_pc[1] ? active_response[31:16]
                                        : active_response[15:0];
    assign starts_cross_word = !cross_pending_q && i_pc[1] &&
                               (i_response_data[17:16] == 2'b11);

    // Keep the sequential-PC decision independent of the decompressor and
    // instruction-output mux. Only a successfully completed compressed
    // instruction advances the PC by two bytes.
    assign pc_increment_2_fast = response_held_q
                               ? (!held_error_q && !held_cross_q &&
                                  (compressed_parcel[1:0] != 2'b11))
                               : (i_response_valid && !i_response_error &&
                                  !cross_pending_q && !starts_cross_word &&
                                  (compressed_parcel[1:0] != 2'b11));
    assign o_pc_increment_2 = pc_increment_2_fast;

    rv32c_decompressor u_decompressor (
        .i_instruction(compressed_parcel),
        .o_instruction(decompressed_instruction),
        .o_illegal(decompressed_illegal)
    );

    always_comb begin
        o_complete        = 1'b0;
        o_instruction     = 32'h0000_0013;
        o_raw_instruction = 32'h0000_0013;
        o_compressed      = 1'b0;
        o_access_fault    = 1'b0;

        if (response_held_q) begin
            o_complete     = 1'b1;
            o_access_fault = held_error_q;
            if (!held_error_q) begin
                if (held_cross_q) begin
                    o_instruction     = held_response_q;
                    o_raw_instruction = held_response_q;
                end else if (compressed_parcel[1:0] != 2'b11) begin
                    o_compressed      = 1'b1;
                    o_raw_instruction = {16'b0, compressed_parcel};
                    o_instruction     = decompressed_illegal
                                      ? {16'b0, compressed_parcel}
                                      : decompressed_instruction;
                end else begin
                    o_instruction     = held_response_q;
                    o_raw_instruction = held_response_q;
                end
            end
        end else if (i_response_valid) begin
            if (cross_pending_q) begin
                o_complete        = 1'b1;
                o_instruction     = {i_response_data[15:0], first_half_q};
                o_raw_instruction = {i_response_data[15:0], first_half_q};
                o_access_fault    = i_response_error;
            end else if (i_response_error) begin
                o_complete     = 1'b1;
                o_access_fault = 1'b1;
            end else if (!starts_cross_word) begin
                o_complete = 1'b1;
                if (compressed_parcel[1:0] != 2'b11) begin
                    o_compressed      = 1'b1;
                    o_raw_instruction = {16'b0, compressed_parcel};
                    o_instruction     = decompressed_illegal
                                      ? {16'b0, compressed_parcel}
                                      : decompressed_instruction;
                end else begin
                    o_instruction     = i_response_data;
                    o_raw_instruction = i_response_data;
                end
            end
        end
    end

    always_ff @(posedge i_clk or negedge i_arst_n) begin
        if (!i_arst_n) begin
            cross_pending_q <= 1'b0;
            response_held_q <= 1'b0;
            held_cross_q    <= 1'b0;
            held_error_q    <= 1'b0;
        end else if (i_flush) begin
            cross_pending_q <= 1'b0;
            response_held_q <= 1'b0;
            held_cross_q    <= 1'b0;
            held_error_q    <= 1'b0;
        end else if (response_held_q) begin
            if (i_consume) begin
                response_held_q <= 1'b0;
                held_cross_q    <= 1'b0;
                held_error_q    <= 1'b0;
            end
        end else if (i_response_valid) begin
            if (!i_response_error && starts_cross_word) begin
                cross_pending_q <= 1'b1;
            end else begin
                // Every remaining valid response is complete: it is either
                // the second cross-word beat, an error, or a non-crossing
                // instruction.
                cross_pending_q <= 1'b0;
                if (!i_consume) begin
                    response_held_q <= 1'b1;
                    held_cross_q    <= cross_pending_q;
                    held_error_q    <= o_access_fault;
                end
            end
        end
    end

    // Payload is observable only while its associated control state is set.
    // Keep it off the asynchronous reset tree so synthesis can use smaller
    // non-resettable flops.
    always_ff @(posedge i_clk) begin
        // A flush invalidates every control bit that can expose this payload.
        // Capturing an arriving stale response on the same edge is therefore
        // harmless and keeps the global redirect/stall network off the data
        // register clock-enable path.
        if (!response_held_q && i_response_valid) begin
            if (!i_response_error && starts_cross_word)
                first_half_q <= i_response_data[31:16];
            else if (!i_consume)
                held_response_q <= cross_pending_q
                                 ? {i_response_data[15:0], first_half_q}
                                 : i_response_data;
        end
    end

endmodule
