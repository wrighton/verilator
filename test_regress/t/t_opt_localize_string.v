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

// Return whether 'name' is in the comma separated list of the +names= plusarg
function automatic bit in_names(string name);
  string list;
  string item;
  if (!$value$plusargs("names=%s", list)) return 0;
  item = "";
  for (int i = 0; i <= list.len(); ++i) begin
    if (i == list.len() || list[i] == ",") begin
      if (item == name) return 1;
      item = "";
    end else begin
      item = {item, list.substr(i, i)};
    end
  end
  return 0;
endfunction

function automatic string hot_fmt(int value);
  string str;
  str = $sformatf("%0d", value);
  return str;
endfunction

module sub #(
    parameter string NAME = ""
) (
    output logic disabled
);
  // Inputs are constant, so evaluated once in cold code, where the locals are localized
  assign disabled = in_names(NAME) || $test$plusargs("disable_all");
endmodule

module t (
    input clk
);
  int cyc = 0;
  string hot;
  logic dis_a, dis_b, dis_c;

  sub #(.NAME("a")) u_a (.disabled(dis_a));
  sub #(.NAME("b")) u_b (.disabled(dis_b));
  sub #(.NAME("c")) u_c (.disabled(dis_c));

  always @(posedge clk) begin
    cyc <= cyc + 1;
    // String locals of functions called in hot code stay members
    hot <= hot_fmt(cyc);
    if (cyc == 3) begin
      `checks(hot, "2");
      `checkd({dis_a, dis_b, dis_c}, 3'b011);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
