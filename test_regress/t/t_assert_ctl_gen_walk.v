// DESCRIPTION: Verilator: Upward assertion control in generated scopes
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

`timescale 1ns / 1ps

module up_far_mid (
    input bit off
);
  initial if (off) $assertoff(0, gb.inner);
endmodule

// The par holding mid has no gb, so gb.inner is found in the par above it
// (IEEE 1800-2023 23.8 c)
module up_far_par #(
    parameter bit HAS = 1,
    parameter bit OFF = 1
);
  int failures = 0;
  int other_failures = 0;
  if (HAS) begin : gb
    if (1) begin : inner
      initial begin
        #1;
        check :
        assert (1'b0)
        else failures++;
      end
    end
    initial begin
      #1;
      other :
      assert (1'b0)
      else other_failures++;
    end
    up_far_par #(
        .HAS(0),
        .OFF(OFF)
    ) sub ();
  end
  else begin : leaf
    up_far_mid m (OFF);
  end
endmodule

module up_far(output bit done);
  up_far_par p0 ();
  up_far_par #(.OFF(0)) p1 ();
  initial begin
    #2;
    `checkd(p0.failures, 0);
    `checkd(p1.failures, 1);
    `checkd(p0.other_failures, 1);
    `checkd(p1.other_failures, 1);
    done = 1;
  end
endmodule

module up_inst_mid (
    input bit off
);
  initial if (off) $assertoff(0, gb.inner);
endmodule

module up_inst_other;
endmodule

// wrap holds an instance named par, but gb is found only in the module par above
// (IEEE 1800-2023 23.8 b)
module up_inst_wrap (
    input bit off
);
  up_inst_other par ();
  up_inst_mid m (off);
endmodule

module up_inst_par #(
    parameter bit OFF = 1
);
  int failures = 0;
  if (1) begin : gb
    if (1) begin : inner
      initial begin
        #1;
        check :
        assert (1'b0)
        else failures++;
      end
    end
  end
  up_inst_wrap w (OFF);
endmodule

module up_inst(output bit done);
  up_inst_par p0 ();
  up_inst_par #(.OFF(0)) p1 ();
  initial begin
    #2;
    `checkd(p0.failures, 0);
    `checkd(p1.failures, 1);
    done = 1;
  end
endmodule

module up_nest_mid (
    input bit off
);
  initial if (off) $assertoff(0, gb.inner);
endmodule

// The mid in par finds gb.inner in par, though a qar holding one is above it; the mid in qar
// finds it in qar (IEEE 1800-2023 23.8 b)
module up_nest_par (
    input bit off
);
  int failures = 0;
  if (1) begin : gb
    if (1) begin : inner
      initial begin
        #1;
        check :
        assert (1'b0)
        else failures++;
      end
    end
  end
  up_nest_mid m (off);
endmodule

module up_nest_qar #(
    parameter bit OFF_P = 1,
    parameter bit OFF_Q = 1
);
  int failures = 0;
  if (1) begin : gb
    if (1) begin : inner
      initial begin
        #1;
        check :
        assert (1'b0)
        else failures++;
      end
    end
  end
  up_nest_par p (OFF_P);
  up_nest_mid m (OFF_Q);
endmodule

module up_nest(output bit done);
  up_nest_qar #(
      .OFF_P(1),
      .OFF_Q(0)
  ) q0 ();
  up_nest_qar #(
      .OFF_P(0),
      .OFF_Q(1)
  ) q1 ();
  initial begin
    #2;
    `checkd(q0.p.failures, 0);
    `checkd(q0.failures, 1);
    `checkd(q1.p.failures, 1);
    `checkd(q1.failures, 0);
    done = 1;
  end
endmodule

// Each mid finds gb.inner in its own parent (IEEE 1800-2023 23.8 b), and the parents are of
// different modules
module up_types_mid (
    input bit off
);
  initial if (off) $assertoff(0, gb.inner);
endmodule

module up_types_par #(
    parameter bit OFF = 1
);
  int failures = 0;
  if (1) begin : gb
    if (1) begin : inner
      initial begin
        #1;
        check :
        assert (1'b0)
        else failures++;
      end
    end
  end
  up_types_mid m (OFF);
endmodule

module up_types_qar #(
    parameter bit OFF = 1
);
  int failures = 0;
  if (1) begin : gb
    if (1) begin : inner
      initial begin
        #1;
        check :
        assert (1'b0)
        else failures++;
      end
    end
  end
  up_types_mid m (OFF);
endmodule

module up_types(output bit done);
  up_types_par p0 ();
  up_types_par #(.OFF(0)) p1 ();
  up_types_qar q0 ();
  up_types_qar #(.OFF(0)) q1 ();
  initial begin
    #2;
    `checkd(p0.failures, 0);
    `checkd(p1.failures, 1);
    `checkd(q0.failures, 0);
    `checkd(q1.failures, 1);
    done = 1;
  end
endmodule

module t;
  wire [3:0] done;
  up_far far_test (done[0]);
  up_inst inst_test (done[1]);
  up_nest nest_test (done[2]);
  up_types types_test (done[3]);
  initial begin
    wait (&done);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
