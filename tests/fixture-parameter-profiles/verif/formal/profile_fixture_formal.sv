module profile_fixture_formal #(
    parameter int unsigned WIDTH = 8,
    parameter bit FEATURE_INVERT = 1'b0
);

  (* anyseq *)logic [WIDTH-1:0] data_i;
  logic [WIDTH-1:0] data_o;

  profile_fixture #(
      .WIDTH(WIDTH),
      .FEATURE_INVERT(FEATURE_INVERT)
  ) dut (
      .*
  );

  always_comb begin
    assert (data_o == (FEATURE_INVERT ? ~data_i : data_i));
  end

endmodule
