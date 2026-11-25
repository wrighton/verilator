// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The clock inputs of modules with several instances see the edges of their connections,
// also at time zero, however the clock reaches the event control

module counter (
    input clk,
    output int count
);
  /*verilator no_inline_module*/
  initial count = 0;
  always @(posedge clk) count <= count + 1;
endmodule

// Passed on to an instance that is inlined into the module
module leaf (
    input clk,
    output int count
);
  /*verilator inline_module*/
  initial count = 0;
  always @(posedge clk) count <= count + 1;
endmodule

module relay (
    input clk,
    output int count
);
  /*verilator no_inline_module*/
  leaf u_leaf (
      .clk(clk),
      .count(count)
  );
endmodule

// Through a net
module via_wire (
    input clk,
    output int count
);
  /*verilator no_inline_module*/
  wire g = clk;
  initial count = 0;
  always @(posedge g) count <= count + 1;
endmodule

// Through a gate
module via_gate (
    input clk,
    input en,
    output int count
);
  /*verilator no_inline_module*/
  wire g;
  assign g = clk & en;
  initial count = 0;
  always @(posedge g) count <= count + 1;
endmodule

// Through combinational logic
module via_comb (
    input clk,
    output int count
);
  /*verilator no_inline_module*/
  logic g;
  always_comb g = clk;
  initial count = 0;
  always @(posedge g) count <= count + 1;
endmodule

// Through a derived net into a module instantiated in turn
module via_child (
    input clk,
    output int count
);
  /*verilator no_inline_module*/
  wire g = ~clk;
  counter u_counter (
      .clk(~g),
      .count(count)
  );
endmodule

// Through a gate shared with a module instantiated in turn
module via_shared_gate (
    input clk,
    input en,
    output int count,
    output int count_child
);
  /*verilator no_inline_module*/
  wire g = clk & en;
  initial count = 0;
  always @(posedge g) count <= count + 1;
  counter u_counter (
      .clk(clk & en),
      .count(count_child)
  );
endmodule

// Directly and through a gate
module direct_and_gate (
    input clk,
    input en,
    output int count,
    output int count_gate
);
  /*verilator no_inline_module*/
  wire g = clk & en;
  initial begin
    count = 0;
    count_gate = 0;
  end
  always @(posedge clk) count <= count + 1;
  always @(posedge g) count_gate <= count_gate + 1;
endmodule

// Through three levels of modules
module level3 (
    input clk,
    output int count
);
  /*verilator no_inline_module*/
  counter u_counter (
      .clk(clk),
      .count(count)
  );
endmodule

module level2 (
    input clk,
    output int count
);
  /*verilator no_inline_module*/
  level3 u_level3 (
      .clk(clk),
      .count(count)
  );
endmodule

module level1 (
    input clk,
    output int count
);
  /*verilator no_inline_module*/
  level2 u_level2 (
      .clk(clk),
      .count(count)
  );
endmodule

class ClockBox;
  bit value;
  function new(bit v);
    value = v;
  endfunction
endclass

module t;
  // High from time zero, which is no rising edge
  logic clk = 1'b1;
  logic clk_n = 1'b0;
  bit en = 1'b1;
  always #5 begin
    clk = ~clk;
    clk_n = ~clk_n;
  end
  int ticks = 0;
  always @(posedge clk) ticks <= ticks + 1;

  // Rises at time zero, which is a rising edge
  logic clk0 = 1'b0;
  initial clk0 = 1'b1;
  always #5 clk0 = ~clk0;
  int ticks0 = 0;
  always @(posedge clk0) ticks0 <= ticks0 + 1;

  // Read from an object constructed by an initial block, which is a rising edge
  ClockBox box;
  initial box = new(1'b1);

  // Set by an initial block only, which is a rising edge
  bit clk_init;
  bit en_init;
  initial clk_init = 1'b1;
  initial en_init = 1'b1;
  int ticks_init = 0;
  always @(posedge clk_init) ticks_init <= ticks_init + 1;
  wire gate_init = clk & en_init;
  int ticks_gate_init = 0;
  always @(posedge gate_init) ticks_gate_init <= ticks_gate_init + 1;

  // Constant, which is a rising edge from the initial value of the port
  localparam bit PC = 1'b1;

  int count[32];
  counter u_c1 (
      .clk(clk),
      .count(count[0])
  );
  counter u_c2 (
      .clk(clk),
      .count(count[1])
  );
  counter u_c3 (
      .clk(~clk_n),
      .count(count[2])
  );
  relay u_r1 (
      .clk(clk),
      .count(count[3])
  );
  relay u_r2 (
      .clk(clk),
      .count(count[4])
  );
  via_wire u_w1 (
      .clk(clk),
      .count(count[5])
  );
  via_wire u_w2 (
      .clk(clk),
      .count(count[6])
  );
  via_gate u_g1 (
      .clk(clk),
      .en(en),
      .count(count[7])
  );
  via_gate u_g2 (
      .clk(clk),
      .en(en),
      .count(count[8])
  );
  via_comb u_m1 (
      .clk(clk),
      .count(count[9])
  );
  via_comb u_m2 (
      .clk(clk),
      .count(count[10])
  );
  via_child u_d1 (
      .clk(clk),
      .count(count[11])
  );
  via_child u_d2 (
      .clk(clk),
      .count(count[12])
  );
  level1 u_l1 (
      .clk(clk),
      .count(count[13])
  );
  level1 u_l2 (
      .clk(clk),
      .count(count[14])
  );
  counter u_e1 (
      .clk(clk0),
      .count(count[15])
  );
  via_wire u_e2 (
      .clk(clk0),
      .count(count[16])
  );
  level1 u_e3 (
      .clk(clk0),
      .count(count[17])
  );
  via_shared_gate u_s1 (
      .clk(clk),
      .en(en),
      .count(count[18]),
      .count_child(count[19])
  );
  via_shared_gate u_s2 (
      .clk(clk),
      .en(en),
      .count(count[20]),
      .count_child(count[21])
  );
  counter u_b1 (
      .clk(box.value),
      .count(count[22])
  );
  counter u_b2 (
      .clk(box.value),
      .count(count[23])
  );
  direct_and_gate u_i1 (
      .clk(clk_init),
      .en(en),
      .count(count[24]),
      .count_gate(count[25])
  );
  direct_and_gate u_i2 (
      .clk(clk_init),
      .en(en),
      .count(count[26]),
      .count_gate(count[27])
  );
  via_gate u_i3 (
      .clk(clk),
      .en(en_init),
      .count(count[28])
  );
  via_gate u_i4 (
      .clk(clk),
      .en(en_init),
      .count(count[29])
  );
  counter u_k1 (
      .clk(1'b1),
      .count(count[30])
  );
  counter u_k2 (
      .clk(PC),
      .count(count[31])
  );

  initial begin
    repeat (7) begin
      @(negedge clk);
      for (int i = 0; i < 15; ++i) `checkd(count[i], ticks);
      for (int i = 15; i < 18; ++i) `checkd(count[i], ticks0);
      for (int i = 18; i < 22; ++i) `checkd(count[i], ticks);
      for (int i = 22; i < 24; ++i) `checkd(count[i], 1);
      for (int i = 24; i < 28; ++i) `checkd(count[i], ticks_init);
      for (int i = 28; i < 30; ++i) `checkd(count[i], ticks_gate_init);
      for (int i = 30; i < 32; ++i) `checkd(count[i], 1);
    end
    `checkd(ticks, 6);
    `checkd(ticks0, 7);
    `checkd(ticks_init, 1);
    `checkd(ticks_gate_init, 7);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
