// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

int probes;  // Bit per probe ID instantiated
int probe_count;  // Number of probes instantiated
int harnesses;  // Number of harnesses instantiated
int harness_checks;  // Number of harness checks done
int watches;  // Number of watches instantiated
int sibling_checks;  // Number of checks of a bound instance's signal by another

interface probe_if #(
    parameter int ID = 0,
    parameter string PATH = ""
) ();
  initial begin
    if (PATH != "") `checks($sformatf("%m"), PATH);
    probes |= 1 << ID;
    ++probe_count;
  end
endinterface

module leaf #(
    parameter int W = 7
) (
    input clk,
    input logic [W-1:0] in
);
  logic [W-1:0] doubled;
  always @(posedge clk) doubled <= in * 2;
endmodule

// Checks the signals and parameters of the instance it is bound into
module harness #(
    parameter int WIDTH = 0
) (
    input clk,
    input logic [6:0] in,
    input logic [6:0] doubled
);
  logic [6:0] prev_in;
  bit started;
  initial begin
    `checkd(WIDTH, 7);
    ++harnesses;
  end
  always @(posedge clk) begin
    if (started) begin
      `checkd(doubled, 7'(prev_in * 2));
      ++harness_checks;
    end
    prev_in <= in;
    started <= 1'b1;
  end
endmodule

// Instantiates the module of the instance it is bound into, and refers into that instance
module watch (
    input clk,
    input logic [6:0] in
);
  leaf ordinary (
      .clk(clk),
      .in(in)
  );
  initial ++watches;
  always @(negedge clk) `checkd(ordinary.in, in);
endmodule

// Has an instance named as the top module, with instances named as in the top module
module lookalike;
  for (genvar g = 0; g < 3; ++g) begin : gen
    leaf u_leaf (
        .clk(1'b0),
        .in(7'd0)
    );
  end
endmodule

module lookalike_top;
  lookalike t ();
endmodule

// Different modules bound with the same instance name
module first_probe #(
    parameter int MARK = 7
);
endmodule

module second_probe #(
    parameter int OTHER = 9
);
endmodule

// Instantiated where binds with paths ending the same name different instances
module common_leaf;
  leaf u (
      .clk(1'b0),
      .in(7'd0)
  );
endmodule

module owner_x;
  common_leaf c ();
  bind c.u first_probe mon ();
endmodule

module owner_y;
  common_leaf c ();
endmodule

// Instantiated where binds with paths ending the same go into distinct generate loops
module common_loop;
  for (genvar i = 0; i < 2; ++i) begin : k
    leaf u (
        .clk(1'b0),
        .in(7'd0)
    );
  end
endmodule

module owner_loop;
  common_loop c ();
  if (1) begin : g
    common_loop c ();
  end
  bind c.k[0].u first_probe mon ();
endmodule

// Bound into one instance, one connected to a signal of the other
module sibling_source;
  logic [6:0] value = 7'd93;
endmodule

module sibling_sink (
    input logic [6:0] din
);
  initial begin
    #1;
    `checkd(din, 93);
    ++sibling_checks;
  end
endmodule

module mid #(
    parameter int BASE = 0
) (
    input clk,
    input logic [6:0] in
);
  if (1) begin : g_on
    for (genvar i = 0; i < 2; ++i) begin : outer
      for (genvar j = 0; j < 2; ++j) begin : inner
        leaf u_leaf (
            .clk(clk),
            .in(in + 7'(BASE + i * 2 + j))
        );
      end
    end
  end
  // Relative to each instance of this module
  bind g_on.outer[1].inner[0].u_leaf harness #(.WIDTH(W)) u_harness (
      .doubled(doubled),
      .*
  );
  // Starting at this module's name
  bind mid.g_on.outer[0].inner[0].u_leaf harness #(.WIDTH(W)) u_harness (.*);
endmodule

module t;
  logic clk = 0;
  logic [6:0] in = 0;
  always #5 clk = ~clk;
  always @(posedge clk) in <= in + 7'd13;

  for (genvar g = 0; g < 3; ++g) begin : gen
    leaf u_leaf (
        .clk(clk),
        .in(in + 7'(g))
    );
  end
  leaf #(7) u_leaf_pos (
      .clk(clk),
      .in(in)
  );

  // An unnamed generate block is not a scope
  generate
    begin
      case (1)
        1: begin : g_case
          leaf u_leaf (
              .clk(clk),
              .in(in)
          );
        end
        default: ;
      endcase
    end
  endgenerate
  if (0) begin : g_a
    leaf u_leaf (
        .clk(clk),
        .in(in)
    );
  end else if (1) begin : g_b
    leaf u_leaf (
        .clk(clk),
        .in(in)
    );
  end

  mid #(.BASE(10)) u_m1 (
      .clk(clk),
      .in(in)
  );
  mid #(.BASE(20)) u_m2 (
      .clk(clk),
      .in(in)
  );
  lookalike_top u_lookalike ();
  // Instances with identical parameters
  mid #(.BASE(30)) u_m3 (
      .clk(clk),
      .in(in)
  );
  mid #(.BASE(30)) u_m4 (
      .clk(clk),
      .in(in)
  );
  leaf u_mon_a (
      .clk(clk),
      .in(in)
  );
  leaf u_mon_b (
      .clk(clk),
      .in(in)
  );
  initial begin
    `checkd(u_mon_a.u_mon.MARK, 7);
    `checkd(u_mon_b.u_mon.OTHER, 9);
  end
  owner_x u_own_x ();
  owner_y u_own_y ();
  owner_loop u_own_loop ();
  initial begin
    `checkd(u_own_loop.c.k[0].u.mon.MARK, 7);
    `checkd(u_own_loop.g.c.k[1].u.mon.OTHER, 9);
  end
  initial begin
    `checkd(u_own_x.c.u.mon.MARK, 7);
    `checkd(u_own_y.c.u.mon.OTHER, 9);
  end
  leaf u_sib_a (
      .clk(clk),
      .in(in)
  );
  leaf u_sib_b (
      .clk(clk),
      .in(in)
  );

  initial begin
    #100;
    // Bound only into the instances named, e.g. not into gen[1], u_m2.g_on.outer[0].inner[1]
    // or u_m4.g_on.outer[1].inner[1]
    `checkd(probes, 'b11111101);
    `checkd(probe_count, 7);
    `checkd(gen[2].u_leaf.u_probe.ID, 2);
    `checkd(u_leaf_pos.u_probe.ID, 4);
    `checkd(harnesses, 8);
    `checkd(harness_checks, 8 * 9);
    `checkd(watches, 1);
    `checkd(sibling_checks, 1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule

// Different parameters for instances of one module
bind t.gen[0].u_leaf probe_if #(
    .ID(0),
    .PATH("t.gen[0].u_leaf.u_probe")
) u_probe ();
bind t.gen[1+1].u_leaf probe_if #(
    .ID(2),
    .PATH("t.gen[2].u_leaf.u_probe")
) u_probe ();
// Deep path through generate blocks
bind t.u_m1.g_on.outer[0].inner[1].u_leaf probe_if #(
    .ID(3),
    .PATH("t.u_m1.g_on.outer[0].inner[1].u_leaf.u_probe")
) u_probe ();
// Instance overriding a parameter by position
bind t.u_leaf_pos probe_if #(
    .ID(4),
    .PATH("t.u_leaf_pos.u_probe")
) u_probe ();
// Through generate case and else if blocks
bind t.g_case.u_leaf probe_if #(
    .ID(5),
    .PATH("t.g_case.u_leaf.u_probe")
) u_probe ();
bind t.g_b.u_leaf probe_if #(
    .ID(6),
    .PATH("t.g_b.u_leaf.u_probe")
) u_probe ();
// Into one of two instances with identical parameters
bind t.u_m3.g_on.outer[1].inner[1].u_leaf probe_if #(
    .ID(7),
    .PATH("t.u_m3.g_on.outer[1].inner[1].u_leaf.u_probe")
) u_probe ();
// A module instantiating the module of the instance
bind t.u_leaf_pos watch u_watch (.*);
// Different modules with the same instance name
bind t.u_mon_a first_probe u_mon ();
bind t.u_mon_b second_probe u_mon ();
// Connected to another instance bound into the same instance
bind t.u_sib_a sibling_source u_source ();
bind t.u_sib_a sibling_sink u_sink (.din(u_source.value));
bind t.u_own_y.c.u second_probe mon ();
bind t.u_own_loop.g.c.k[1].u second_probe mon ();
