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

  // Nothing for the sampler to enumerate: a constraint on state only, and an empty queue
  class StateOnly;
    int limit;
    constraint c {limit > 3;}
  endclass

  class EmptyQueue;
    rand bit [6:0] q[$];
    constraint c {foreach (q[i]) q[i] < 7'd10;}
  endclass

  class EmptyRows;
    rand bit [6:0] rows[][];
    function new;
      rows = new[2];
    endfunction
    constraint c {foreach (rows[i, j]) rows[i][j] < 7'd10;}
  endclass

  // Resized and partly frozen between calls of one constraint set
  class Interleaved;
    rand bit [6:0] q[$];
    rand bit [6:0] x;
    constraint c {
      foreach (q[i]) q[i] < 7'd10;
      x < 7'd10;
    }
  endclass

  // A scalar beside an empty queue still has a space to sample
  class ScalarAndEmpty;
    rand bit [6:0] s;
    rand bit [6:0] q[$];
    constraint c {
      s < 7'd10;
      foreach (q[i]) q[i] < 7'd10;
    }
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
      automatic StateOnly met = new;
      automatic StateOnly unmet = new;
      automatic EmptyQueue empty = new;
      automatic EmptyRows rows = new;
      automatic ScalarAndEmpty mixed = new;
      met.limit = 5;
      unmet.limit = 2;
      // Repeated, as the sampler first sees each constraint set without sampling it
      for (int i = 0; i < 4; ++i) begin
        randomize_result = met.randomize();
        `checkd(randomize_result, 1);
        randomize_result = unmet.randomize();
        `checkd(randomize_result, 0);
        randomize_result = empty.randomize();
        `checkd(randomize_result, 1);
        `checkd(empty.q.size(), 0);
        randomize_result = rows.randomize();
        `checkd(randomize_result, 1);
        `checkd(rows.rows.size(), 2);
        `checkd(rows.rows[0].size(), 0);
        randomize_result = mixed.randomize();
        `checkd(randomize_result, 1);
        `checkd(mixed.s < 7'd10, 1'b1);
        `checkd(mixed.q.size(), 0);
      end
    end

    begin
      automatic EmptyQueue resized = new;
      automatic Interleaved il = new;
      // Twice per size, so the sampler samples each set it has seen once
      for (int i = 0; i < 2; ++i) begin
        for (int k = 0; k < 2; ++k) begin
          resized.q = '{};
          randomize_result = resized.randomize();
          `checkd(randomize_result, 1);
          `checkd(resized.q.size(), 0);
        end
        for (int k = 0; k < 2; ++k) begin
          resized.q = '{7'd99, 7'd99, 7'd99};
          randomize_result = resized.randomize();
          `checkd(randomize_result, 1);
          foreach (resized.q[j]) `checkd(resized.q[j] < 7'd10, 1'b1);
        end
      end
      for (int i = 0; i < 4; ++i) begin
        il.q = '{7'd99};
        randomize_result = il.randomize();
        `checkd(randomize_result, 1);
        `checkd(il.q[0] < 7'd10, 1'b1);
        `checkd(il.x < 7'd10, 1'b1);
        il.x.rand_mode(0);
        il.q = '{7'd99, 7'd99, 7'd99};
        randomize_result = il.randomize();
        `checkd(randomize_result, 1);
        foreach (il.q[j]) `checkd(il.q[j] < 7'd10, 1'b1);
        il.x.rand_mode(1);
      end
    end

    begin
      // Each std::randomize call site repeated on its own, so the sampler sees the same set
      // again; every call registers its arrays afresh
      automatic bit [6:0] sq[$] = '{7'd99, 7'd99, 7'd99};
      automatic bit [6:0] eq[$];
      for (int i = 0; i < 4; ++i) begin
        randomize_result = std::randomize(sq) with {foreach (sq[j]) sq[j] < 7'd10;};
        `checkd(randomize_result, 1);
        foreach (sq[j]) `checkd(sq[j] < 7'd10, 1'b1);
      end
      for (int i = 0; i < 4; ++i) begin
        randomize_result = std::randomize(eq) with {foreach (eq[j]) eq[j] < 7'd10;};
        `checkd(randomize_result, 1);
        `checkd(eq.size(), 0);
      end
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
