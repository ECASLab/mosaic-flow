module flow_fixture_formal;
  localparam int unsigned DATA_WIDTH = 32;

  (* gclk *)logic                  clk_i;
  (* anyseq *)logic                  rst_ni;
  (* anyseq *)logic                  enable_i;
  (* anyseq *)logic [DATA_WIDTH-1:0] data_i;
  logic [DATA_WIDTH-1:0] data_o;
  logic                  past_valid = 1'b0;

  flow_fixture #(.DATA_WIDTH(DATA_WIDTH)) dut (.*);

  always_comb begin
    if (!rst_ni) begin
      assert (data_o == '0);
    end
  end

  always_ff @(posedge clk_i) begin
    past_valid <= 1'b1;

    if (past_valid && rst_ni && $past(rst_ni)) begin
      if ($past(enable_i)) begin
        assert (data_o == $past(data_i));
      end else begin
        assert (data_o == $past(data_o));
      end
    end
  end

endmodule
