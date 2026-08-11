module flow_fixture_tb;
  localparam int unsigned DATA_WIDTH = 32;

  logic                  clk_i;
  logic                  rst_ni;
  logic                  enable_i;
  logic [DATA_WIDTH-1:0] data_i;
  logic [DATA_WIDTH-1:0] data_o;

  always #5ns clk_i = ~clk_i;

  flow_fixture #(.DATA_WIDTH(DATA_WIDTH)) dut (.*);

  initial begin
    clk_i    = 1'b0;
    rst_ni   = 1'b0;
    enable_i = 1'b0;
    data_i   = '0;

    repeat (2) @(posedge clk_i);
    @(negedge clk_i);
    rst_ni   = 1'b1;
    data_i   = 32'h1234_5678;
    enable_i = 1'b1;
    @(posedge clk_i);
    @(negedge clk_i);
    enable_i = 1'b0;

    assert (data_o == 32'h1234_5678)
    else $fatal(1, "Unexpected output: %h", data_o);

    repeat (2) @(posedge clk_i);
    @(negedge clk_i);
    $finish;
  end
endmodule
