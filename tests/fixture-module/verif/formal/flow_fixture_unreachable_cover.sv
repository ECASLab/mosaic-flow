// Negative formal fixture proving that unreachable cover statements fail the gate.
module flow_fixture_unreachable_cover;

  logic clk_i;

  always_ff @(posedge clk_i) begin
    cover (1'b0);
  end

endmodule
