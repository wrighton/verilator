// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// "Expressions used in assertion action blocks do not contribute to the implicit sensitivity
// list of an always_comb" (IEEE 1800-2023 9.2.2.2.1). A deferred assertion item is in an
// always_comb (IEEE 1800-2023 16.4).
module t (
    input clk
);
  int cyc = 0;
  bit a = 0;  // Changes on every clock edge
  bit b = 0;  // Changes on every fourth clock edge
  bit [3:0] r = 0;  // Changes on every clock edge
  bit [3:0] rAtB = 0;  // The value of r at the last change of b

  // Test: two assertions counting their passes in one variable, so neither is its only writer
  int p;
  function void bump_p();
    p++;
  endfunction
  function void idle();
  endfunction
  assert final (a) bump_p();
  else idle();
  assert final (!a) bump_p();
  else idle();

  // Test: a variable read only in the action block does not wake the assertion
  bit [3:0] seen;
  function void see(bit [3:0] v);
    seen = v;
  endfunction
  assert final (b) see(r);
  else see(r);
  bit [3:0] seenImm;
  always_comb
    assert (b) seenImm = r;
    else seenImm = r;

  // Test: nor does an argument of a function that is not inlined, called in both action blocks
  bit [3:0] seenCall;
  function automatic bit [3:0] passOn(bit [3:0] v);
    // verilator no_inline_task
    return v;
  endfunction
  always_comb
    assert (b) seenCall = passOn(r);
    else seenCall = passOn(r);

  // Test: one also read in the assertion expression does
  bit [3:0] seenR;
  function void seeR(bit [3:0] v);
    seenR = v;
  endfunction
  assert final (r[0]) seeR(r);
  else seeR(r);

  // Test: so is one read elsewhere in the always_comb, though not used
  bit [3:0] seenUnused;
  bit [3:0] unused;
  always_comb begin
    assert (b) seenUnused = r;
    else seenUnused = r;
    unused = r;
  end

  // Test: an always @* is sensitive to its action blocks (IEEE 1800-2023 9.4.2.2)
  bit [3:0] seenStar;
  always @*
    assert (b) seenStar = r;
    else seenStar = r;

  always @(b) rAtB = r;

  always @(posedge clk) begin
    if (cyc > 0) begin
      // One pass at time zero and one per change of a
      `checkd(p, 1 + cyc);
      `checkd(seen, rAtB);
      `checkd(seenImm, rAtB);
      `checkd(seenCall, rAtB);
      `checkd(seenR, r);
      `checkd(seenUnused, r);
      `checkd(seenStar, r);
    end
    cyc <= cyc + 1;
    a <= !a;
    r <= r + 4'd3;
    if (cyc % 4 == 3) b <= !b;
    if (cyc == 20) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
