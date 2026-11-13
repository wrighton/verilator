// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2019 Peter Monsson
// SPDX-License-Identifier: CC0-1.0

module t (  /*AUTOARG*/
    // Inputs
    clk
);

  input clk;
  int cyc;

  Test test (  /*AUTOINST*/
      // Inputs
      .clk(clk),
      .cyc(cyc)
  );

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 10) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

endmodule

module Test (
    input clk,
    input int cyc
);

`ifdef FAIL_ASSERT_1
  assert property (@(posedge clk) disable iff (0) 0)
  else $display("wrong disable");
`endif

  assert property (@(posedge clk) disable iff (1) 0) $stop;
  else $stop;

  assert property (@(posedge clk) disable iff (1) 1) $stop;
  else $stop;

  assert property (@(posedge clk) disable iff (0) 1);

  // Pass 1st cycle
  assert property (@(cyc) disable iff (cyc != $sampled(cyc)) cyc == 0);

  // Clocking event by name, with disable iff (IEEE 1800-2023 16.12)
  clocking cb @(posedge clk);
  endclocking
  logic dis = 0;
  // Changes away from clk posedges, so its current value matches the sampled cyc
  always @(negedge clk) dis <= cyc >= 3 && cyc < 6;
  property p_named_clk(x, event ck);
    @ck disable iff (dis) x;
  endproperty
  int npass = 0;
  assert property (@cb disable iff (dis) !(cyc >= 3 && cyc < 6)) npass++;
  else $stop;
  assert property (disable iff (dis) @cb !(cyc >= 3 && cyc < 6)) npass++;
  else $stop;
  event ev;
  always @(posedge clk) ->ev;
  assert property (@ev disable iff (dis) !(cyc >= 3 && cyc < 6)) npass++;
  else $stop;
  assert property (p_named_clk(!(cyc >= 3 && cyc < 6), ev)) npass++;
  else $stop;
  // Each passed on cycles 0-2 and 6-8, disabled on 3-5
  always @(posedge clk) if (cyc == 9 && npass != 4 * 6) $stop;

  //
  // Cover properties behave differently
  //

  cover property (@(posedge clk) disable iff (1) 1) $stop;

  cover property (@(posedge clk) disable iff (1) 0) $stop;

  cover property (@(posedge clk) disable iff (0) 1) $display("*COVER: ok");

  cover property (@(posedge clk) disable iff (0) 0) $stop;

endmodule
