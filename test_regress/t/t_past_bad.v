// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2018 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input d,
    input clk,
    input int num
);

  always @(posedge clk) begin
    if ($past(d, num)) $stop;  // IEEE 16.9.3 must be const
    if ($past(d, 0)) $stop;  // IEEE 16.9.3 must be >= 0
    if ($past(d, 10000)) $stop;  // TICKCOUNT
    if ($past(d, 32'h7fffffff)) $stop;
    if ($past(d, 32'h7ffffffe)) $stop;
    if ($past(d, 32'h7ffffffc)) $stop;
  end

  // An automatic variable is not legal in the clocking event (IEEE 1800-2023 16.9.3)
  logic [3:0] clks;
  logic [3:0] q;
  always @(posedge clk) begin
    for (int i = 0; i < 4; i++) q[i] <= $rose(d, clks[i]);
    for (int i = 0; i < 4; i++) q[i] <= $past(d, 1, , @(posedge clks[i]));
    for (int i = 0; i < 4; i++) q[i] <= $stable(d, @(negedge clks[i]));
    for (int i = 0; i < 4; i++) q[i] <= $fell(d, clks[1]);  // Legal
  end
  always @(posedge clk) begin
    automatic logic c = clks[0];
    q[0] <= $fell(d, c);
  end
  task automatic stable_on(input logic c, output logic o);
    o = $stable(d, c);
  endtask

  sub sub_i (.d);
endmodule

// A subroutine argument in an automatic module is automatic (IEEE 1800-2023 6.21)
module automatic sub (
    input d
);
  function logic rose_on(input logic c);
    return $rose(d, c);
  endfunction
endmodule
