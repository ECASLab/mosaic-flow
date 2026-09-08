// Negative-test-only checker that qualifies simulator assertion propagation.
module flow_fixture_failure_sva (
    input logic clk_i,
    input logic rst_ni
);

  always @(posedge clk_i) begin
    if (rst_ni) begin
      assert (1'b0)
      else $fatal(1, "INJECTED_ASSERTION_FAILURE");
    end
  end

endmodule

bind flow_fixture flow_fixture_failure_sva i_flow_fixture_failure_sva (.*);
