// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Repeated randomize() of each kind of constraint set: scalars (UniGen2 and
// diversity pins by default), an array (XOR diversity rounds) and
// solve...before (phased, with a diversity round per layer), and a randc
// cycle. The drivers check the sampler named in the solver log.
// The variables a0 and d0 have the form of the runtime's numbered diversity pin
// and UniGen2 literals (__Va<N>, __Vd<N>) without the prefix, and must not clash.

module t;

  class Scalars;
    rand bit [6:0] a0;
    rand bit [14:0] b;
    constraint c {
      a0 < 7'd100;
      b > 15'(a0);
    }
  endclass

  class Elems;
    rand bit [30:0] d0[3];
    constraint c {foreach (d0[i]) d0[i] < 31'd1000;}
  endclass

  class Ordered;
    rand bit [4:0] x;
    rand bit [32:0] y;
    constraint c {
      solve x before y;
      x < 5'd20;
      y <= 33'(x);
    }
  endclass

  class Cyclic;
    randc bit [2:0] r;
  endclass

  // Constraints all off: the variables they name are as free as those in no constraint,
  // whichever the sampler (IEEE 1800-2023 18.9)
  class Off;
    rand bit [6:0] f[4];
    rand bit [6:0] g;
    constraint c {
      foreach (f[i]) f[i] < 7'd10;
      g < 7'd10;
    }
  endclass

  // A variable whose constraints are off beside constraints that cannot hold
  class Unmet;
    rand bit [6:0] f;
    int limit;
    constraint c {limit > 3;}
    constraint d {f < 7'd10;}
  endclass

  class Obj;
    rand bit [6:0] x;
  endclass

  // Member objects a constraint names through their array of handles, beside a unique array
  class Handles;
    rand Obj objs[2];
    rand bit [6:0] w[3];
    constraint c {foreach (objs[i]) objs[i].x < 7'd10;}
    constraint u {unique {w};}
    function new;
      foreach (objs[i]) objs[i] = new;
    endfunction
  endclass

  initial begin
    Scalars s;
    Elems e;
    Ordered o;
    Cyclic c;
    int randomize_result;
    bit [14:0] first_b;
    bit [30:0] first_d0;
    bit b_varied;
    bit d0_varied;
    bit [7:0] seen;
    s = new;
    e = new;
    o = new;
    c = new;
    for (int i = 0; i < 20; ++i) begin
      randomize_result = s.randomize();
      `checkd(randomize_result, 1);
      `checkd(s.a0 < 7'd100, 1'b1);
      `checkd(s.b > 15'(s.a0), 1'b1);
      if (i == 0) first_b = s.b;
      else if (s.b != first_b) b_varied = 1'b1;
      randomize_result = e.randomize();
      `checkd(randomize_result, 1);
      foreach (e.d0[j]) `checkd(e.d0[j] < 31'd1000, 1'b1);
      if (i == 0) first_d0 = e.d0[0];
      else if (e.d0[0] != first_d0) d0_varied = 1'b1;
      randomize_result = o.randomize();
      `checkd(randomize_result, 1);
      `checkd(o.x < 5'd20, 1'b1);
      `checkd(o.y <= 33'(o.x), 1'b1);
    end
    // Only Verilator's sampler promises varied results; the solver's depend on the solver
    if ($test$plusargs("check_varied")) begin
      `checkd(b_varied, 1'b1);
      `checkd(d0_varied, 1'b1);
    end

    // Two full randc cycles: the second exhausts the first's history and retries
    repeat (2) begin
      seen = '0;
      repeat (8) begin
        randomize_result = c.randomize();
        `checkd(randomize_result, 1);
        `checkd(seen[c.r], 1'b0);
        seen[c.r] = 1'b1;
      end
    end

    // randomize(null) only checks the current values: no sampling, values unchanged
    s.a0 = 7'd5;
    s.b = 15'd6;
    randomize_result = s.randomize(null);
    `checkd(randomize_result, 1);
    `checkd(s.a0, 5);
    `checkd(s.b, 6);
    s.b = 15'd5;
    randomize_result = s.randomize(null);
    `checkd(randomize_result, 0);
    `checkd(s.a0, 5);
    `checkd(s.b, 5);

    begin
      automatic Off off = new;
      automatic Handles h = new;
      automatic Unmet unmet = new;
      automatic int big = 0;
      off.c.constraint_mode(0);
      // Of 250 values, about 230 at 10 or more
      for (int i = 0; i < 50; ++i) begin
        randomize_result = off.randomize();
        `checkd(randomize_result, 1);
        foreach (off.f[j]) if (off.f[j] >= 7'd10) ++big;
        if (off.g >= 7'd10) ++big;
        randomize_result = h.randomize();
        `checkd(randomize_result, 1);
        foreach (h.objs[j]) `checkd(h.objs[j].x < 7'd10, 1'b1);
        `checkd(h.w[0] != h.w[1] && h.w[0] != h.w[2] && h.w[1] != h.w[2], 1'b1);
      end
      `checkd(big > 150, 1'b1);
      unmet.d.constraint_mode(0);
      unmet.limit = 2;
      unmet.f = 7'd5;
      randomize_result = unmet.randomize();
      `checkd(randomize_result, 0);
      `checkd(unmet.f, 5);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
