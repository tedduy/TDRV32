module iterative_divider #(
  parameter int N = 32
)(
  input  logic             i_clk,
  input  logic             i_arst_n,
  input  logic             i_start,
  input  logic             i_consume,
  input  logic [N-1:0]     i_dividend,
  input  logic [N-1:0]     i_divisor,
  input  logic [1:0]       i_operation, // 00=DIV, 01=DIVU, 10=REM, 11=REMU
  output logic             o_busy,
  output logic             o_done,
  output logic [N-1:0]     o_result
);

  localparam int COUNT_WIDTH = (N <= 2) ? 1 : $clog2(N);
  localparam logic [COUNT_WIDTH-1:0] LAST_ITERATION = COUNT_WIDTH'(N - 1);

  typedef enum logic [1:0] {
    DIV_IDLE,
    DIV_RUN,
    DIV_DONE
  } div_state_t;

  div_state_t state_q;
  logic [COUNT_WIDTH-1:0] iteration_q;
  logic [N-1:0] dividend_q, divisor_q, quotient_q;
  logic [N-1:0] remainder_q;
  logic quotient_negative_q, remainder_negative_q;
  logic select_remainder_q, special_q;
  logic [N-1:0] special_result_q;

  logic signed_operation;
  logic dividend_negative, divisor_negative;
  logic [N-1:0] dividend_magnitude, divisor_magnitude;
  logic divide_by_zero, signed_overflow;
  logic [N:0] shifted_remainder;
  logic [N-1:0] remainder_next;
  logic [N-1:0] dividend_next, quotient_next;
  logic [N-1:0] quotient_corrected, remainder_corrected;
  logic [N-1:0] normal_result_next;
  logic final_iteration;

  assign signed_operation  = !i_operation[0];
  assign dividend_negative = signed_operation && i_dividend[N-1];
  assign divisor_negative  = signed_operation && i_divisor[N-1];
  assign dividend_magnitude = dividend_negative ? (~i_dividend + 1'b1)
                                                   : i_dividend;
  assign divisor_magnitude  = divisor_negative ? (~i_divisor + 1'b1)
                                                 : i_divisor;
  assign divide_by_zero = (i_divisor == '0);
  assign signed_overflow = signed_operation &&
                           (i_dividend == {1'b1, {(N-1){1'b0}}}) &&
                           (i_divisor == {N{1'b1}});

  // Restoring unsigned division. Each cycle shifts one dividend bit into the
  // partial remainder and produces one quotient bit.
  assign shifted_remainder = {remainder_q[N-1:0], dividend_q[N-1]};
  assign dividend_next = {dividend_q[N-2:0], 1'b0};
  assign remainder_next = (shifted_remainder >= {1'b0, divisor_q})
                        ? shifted_remainder[N-1:0] - divisor_q
                        : shifted_remainder[N-1:0];
  assign quotient_next = {quotient_q[N-2:0],
                          shifted_remainder >= {1'b0, divisor_q}};

  assign quotient_corrected = quotient_negative_q
                            ? (~quotient_next + 1'b1) : quotient_next;
  assign remainder_corrected = remainder_negative_q
                             ? (~remainder_next + 1'b1)
                             : remainder_next;
  assign normal_result_next = select_remainder_q ? remainder_corrected
                                                  : quotient_corrected;
  assign final_iteration = (state_q == DIV_RUN) &&
                           (iteration_q == LAST_ITERATION);

  assign o_busy = (state_q != DIV_IDLE);
  assign o_done = (state_q == DIV_DONE) || final_iteration;
  assign o_result = special_q ? special_result_q :
                    final_iteration ? normal_result_next :
                    select_remainder_q ? remainder_q[N-1:0] : quotient_q;

  always_ff @(posedge i_clk or negedge i_arst_n) begin
    if (!i_arst_n) begin
      state_q <= DIV_IDLE;
    end else begin
      unique case (state_q)
        DIV_IDLE: begin
          if (i_start)
            state_q <= DIV_RUN;
        end

        DIV_RUN: begin
          if (final_iteration) begin
            if (i_consume)
              state_q <= DIV_IDLE;
            else
              state_q <= DIV_DONE;
          end
        end

        DIV_DONE: begin
          if (i_consume)
            state_q <= DIV_IDLE;
        end

        // Defensive recovery for an invalid encoded FSM state.
        /* verilator coverage_off */
        default: state_q <= DIV_IDLE;
        /* verilator coverage_on */
      endcase
    end
  end

  // All datapath state is overwritten on i_start. Only the FSM requires an
  // asynchronous reset; payload flops remain unreset to reduce reset-tree area
  // and fanout without changing operation latency or visible results.
  always_ff @(posedge i_clk) begin
    unique case (state_q)
      DIV_IDLE: begin
        if (i_start) begin
          iteration_q          <= '0;
          dividend_q           <= dividend_magnitude;
          divisor_q            <= divisor_magnitude;
          quotient_q           <= '0;
          remainder_q          <= '0;
          quotient_negative_q  <= dividend_negative ^ divisor_negative;
          remainder_negative_q <= dividend_negative;
          select_remainder_q   <= i_operation[1];
          special_q            <= divide_by_zero || signed_overflow;
          if (divide_by_zero)
            special_result_q <= i_operation[1] ? i_dividend : {N{1'b1}};
          else if (i_operation[1])
            special_result_q <= '0;
          else
            special_result_q <= i_dividend;
        end
      end

      DIV_RUN: begin
        if (final_iteration) begin
          // The completed result is captured below; the original operands are
          // dead in DIV_DONE. Clear them independently of i_consume so
          // downstream backpressure cannot enter their wide feedback muxes.
          dividend_q <= '0;
          divisor_q  <= '0;
          if (!special_q) begin
            quotient_q  <= quotient_corrected;
            remainder_q <= remainder_corrected;
          end
        end else begin
          if (!special_q) begin
            dividend_q  <= dividend_next;
            quotient_q  <= quotient_next;
            remainder_q <= remainder_next;
          end
          iteration_q <= iteration_q + 1'b1;
        end
      end

      default: begin end
    endcase
  end

endmodule
