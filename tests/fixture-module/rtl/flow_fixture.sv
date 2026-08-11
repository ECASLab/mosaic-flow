module flow_fixture #(
    parameter int unsigned DATA_WIDTH = 32
) (
    input  logic                  clk_i,
    input  logic                  rst_ni,
    input  logic                  enable_i,
    input  logic [DATA_WIDTH-1:0] data_i,
    output logic [DATA_WIDTH-1:0] data_o
);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      data_o <= '0;
    end else if (enable_i) begin
      data_o <= data_i;
    end
  end

endmodule
