// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Sequences whose body is only a select
module t (
  input clk
);
  int cyc = 0;
  logic [7:0] len = 0;
  logic arr[4] = '{default: 0};

  always @(posedge clk) begin
    cyc <= cyc + 1;
    len <= len + 8'd3;
    arr[1] <= ~len[2];
    if (cyc == 20) $finish;
  end

  sequence seq_bit;
    len[0];
  endsequence
  sequence seq_range;
    len[2:1];
  endsequence
  sequence seq_var;
    len[cyc[2:0]];
  endsequence
  sequence seq_elem;
    arr[1];
  endsequence
  sequence seq_part;
    len[cyc[2:0]+:1];
  endsequence
  sequence seq_formal(logic [7:0] v, logic [2:0] i);
    v[i];
  endsequence

  int fails_bit = 0, ref_fails_bit = 0;
  assert property (@(posedge clk) seq_bit)
  else fails_bit++;
  assert property (@(posedge clk) len[0])
  else ref_fails_bit++;

  int fails_range = 0, ref_fails_range = 0;
  assert property (@(posedge clk) seq_range)
  else fails_range++;
  assert property (@(posedge clk) len[2:1] != 2'b0)
  else ref_fails_range++;

  int fails_var = 0, ref_fails_var = 0;
  assert property (@(posedge clk) seq_var)
  else fails_var++;
  assert property (@(posedge clk) len[cyc[2:0]])
  else ref_fails_var++;

  int fails_elem = 0, ref_fails_elem = 0;
  assert property (@(posedge clk) seq_elem)
  else fails_elem++;
  assert property (@(posedge clk) arr[1])
  else ref_fails_elem++;

  int fails_part = 0, ref_fails_part = 0;
  assert property (@(posedge clk) seq_part)
  else fails_part++;
  assert property (@(posedge clk) len[cyc[2:0]+:1])
  else ref_fails_part++;

  int fails_formal = 0, ref_fails_formal = 0;
  assert property (@(posedge clk) seq_formal(len, cyc[2:0]))
  else fails_formal++;
  assert property (@(posedge clk) len[cyc[2:0]])
  else ref_fails_formal++;

  // Counts read in final (Postponed) to avoid same-timestep races.
  final begin
    `checkd(fails_bit, ref_fails_bit);
    `checkd(fails_bit, 11);
    `checkd(fails_range, ref_fails_range);
    `checkd(fails_range, 6);
    `checkd(fails_var, ref_fails_var);
    `checkd(fails_var, 11);
    `checkd(fails_elem, ref_fails_elem);
    `checkd(fails_elem, 10);
    `checkd(fails_part, ref_fails_part);
    `checkd(fails_part, 11);
    `checkd(fails_formal, ref_fails_formal);
    `checkd(fails_formal, 11);
    $write("*-* All Finished *-*\n");
  end
endmodule
