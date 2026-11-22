// DESCRIPTION: Verilator: Resolve mixed assertion control scope paths per caller
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

interface bus (input bit clk);
  int selected_count;
  int other_count;
  a: assert property (@(posedge clk) 1'b0) else selected_count++;
  b: assert property (@(posedge clk) 1'b0) else other_count++;
endinterface

module controller #(parameter bit WHOLE_SCOPE = 0);
  if (WHOLE_SCOPE) begin
    initial $assertoff(0, holder.p);
  end else begin
    initial $assertoff(0, holder.p.a);
  end
endmodule

module through_port #(parameter bit WHOLE_SCOPE = 0) (bus p);
  controller #(.WHOLE_SCOPE(WHOLE_SCOPE)) c ();
endmodule

module through_generate #(parameter bit WHOLE_SCOPE = 0) (input bit clk);
  if (1) begin : p
    int selected_count;
    int other_count;
    a: assert property (@(posedge clk) 1'b0) else selected_count++;
    b: assert property (@(posedge clk) 1'b0) else other_count++;
  end
  controller #(.WHOLE_SCOPE(WHOLE_SCOPE)) c ();
endmodule

module port_parent #(parameter bit WHOLE_SCOPE = 0) (bus p);
  through_port #(.WHOLE_SCOPE(WHOLE_SCOPE)) holder (p);
endmodule

module generate_parent #(parameter bit WHOLE_SCOPE = 0) (input bit clk);
  through_generate #(.WHOLE_SCOPE(WHOLE_SCOPE)) holder (clk);
endmodule

module t;
  bit clk;
  bus p (clk);
  bus q (clk);
  port_parent x (p);
  generate_parent y (clk);
  generate_parent #(.WHOLE_SCOPE(1)) z (clk);
  port_parent #(.WHOLE_SCOPE(1)) w (q);

  initial begin
    #1 clk = 1;
    #1;
    `checkd(p.selected_count, 0);
    `checkd(p.other_count, 1);
    `checkd(y.holder.p.selected_count, 0);
    `checkd(y.holder.p.other_count, 1);
    `checkd(q.selected_count, 0);
    `checkd(q.other_count, 0);
    `checkd(z.holder.p.selected_count, 0);
    `checkd(z.holder.p.other_count, 0);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
