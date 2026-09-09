module profile_fixture_tb #(
    parameter int unsigned WIDTH = 8,
    parameter bit FEATURE_INVERT = 1'b0
);

  logic [WIDTH-1:0] data_i;
  logic [WIDTH-1:0] data_o;
  logic [WIDTH-1:0] expected;

  profile_fixture #(
      .WIDTH(WIDTH),
      .FEATURE_INVERT(FEATURE_INVERT)
  ) dut (
      .*
  );

  initial begin
    data_i = '1;
    #1ns;
    expected = FEATURE_INVERT ? '0 : '1;
    assert (data_o == expected)
    else $fatal(1, "Unexpected profile output: %h", data_o);
    $finish;
  end

endmodule
