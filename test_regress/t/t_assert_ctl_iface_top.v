// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2017 Josh Redford
// SPDX-License-Identifier: CC0-1.0

interface top_iface_upward;
  initial $assertoff(0, my_if.checks.check_data);
endinterface

interface my_if #(
    parameter int EXPECT = 1
);

  logic valid;
  logic [7:0] data;

  modport slave_mp(input valid, input data);

  modport master_mp(output valid, output data);

  top_iface_upward ctl ();

  if (1) begin : checks
    initial begin
      $assertoff(0, check_data);
      check_data : assert (data != EXPECT[7:0]);
    end
  end

endinterface

module top_iface_ctl (
    my_if p
);
  initial $assertoff(0, p.checks);
endmodule

module t (
    input wire clk,
    my_if.slave_mp in_if,
    my_if.master_mp out_if
);

  my_if #(.EXPECT(2)) my_i ();
  top_iface_ctl local_ctl (.p(my_i));
  top_iface_ctl input_ctl (.p(in_if));
  top_iface_ctl output_ctl (.p(out_if));

  always @(posedge clk) begin
    my_i.valid <= in_if.valid;
    my_i.data <= in_if.data;
  end

  assign out_if.valid = my_i.valid;
  assign out_if.data = my_i.data;

endmodule
