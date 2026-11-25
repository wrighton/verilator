#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

# Whether the combinational update of the wrapper of a library may reuse its results, and why not

import vltest_bootstrap

test.scenarios('vlt')

CASES = (
    # Assertions and what they report do not affect the outputs, nor random clocked state
    ("reused", None, """
  assign o = a + 8'd1;
  always_comb if (a == 8'hff) $display("[%0t] saturated", $time);
  always_comb assert #0 (a != 8'hfe) else $error("bad at %0t", $time);
  assert property (@(posedge clk) a != 8'hfd);
  int rnd;
  always_ff @(posedge clk) rnd <= $random;
"""),
    # Nor what logic affecting them reports
    ("reported", None, """
  logic [7:0] w;
  function automatic logic [7:0] add1(input logic [7:0] v);
    /*verilator no_inline_task*/
    return v + 8'd1;
  endfunction
  always_comb begin
    if (a == 8'hff) begin
      w = 8'd0;
      $display("[%0t] saturated", $time);
    end else if (a == 8'hfe) begin
      w = 8'd1;
      $stop;
    end else if (a == 8'hfd) begin
      w = 8'd2;
      $finish;
    end else begin
      w = add1(a);
    end
  end
  assign o = w;
"""),
    # Reading a public variable, logic runs at every evaluation
    ("every_eval", "logic run at every evaluation with effects", """
  logic [7:0] st = 0;
  logic [7:0] pr  /*verilator public_flat_rw*/ = 8'd3;
  always @(posedge clk) st <= st + a;
  assign o = st ^ a;
  always_comb begin
    if (pr[0]) $display("[%0t] blk eval a=%0d", $time, a);
    assert (pr != 8'd3 || a != 8'd5) else $error("a is 5 at %0t", $time);
  end
"""),
    # Nor if it reads a file, outside the outputs' logic
    ("every_eval_file", "logic run at every evaluation with effects", """
  int observe  /*verilator public_flat_rw*/ = 1;
  int fd, last_byte;
  initial fd = $fopen("letters.txt", "r");
  assign o = a + 8'd1;
  always_comb begin
    if (observe != 0 && fd != 0) last_byte = $fgetc(fd);
    else last_byte = -1;
  end
  final $display("LAST=%0d", last_byte);
"""),
    # Nor if it calls a function having one
    ("every_eval_call", "logic run at every evaluation with effects", """
  logic [7:0] pr  /*verilator public_flat_rw*/ = 8'd3;
  logic [7:0] seen;
  function automatic logic [7:0] report(input logic [7:0] v);
    /*verilator no_inline_task*/
    $display("[%0t] v=%0d", $time, v);
    return v;
  endfunction
  assign o = a;
  always_comb seen = report(pr);
"""),
    # Nor if it triggers an event, which wakes logic without a change of value
    ("every_eval_event", "logic run at every evaluation with effects", """
  logic [7:0] pr  /*verilator public_flat_rw*/ = 8'd3;
  event ev;
  int cnt = 0;
  assign o = a;
  // verilator lint_off LATCH
  always_comb if (pr[0]) -> ev;
  // verilator lint_on LATCH
  always @(ev) cnt++;
  final $display("CNT=%0d", cnt);
"""),
    # Nor if it keeps a value from its previous evaluation
    ("every_eval_state", "logic run at every evaluation keeping state", """
  logic [7:0] pr  /*verilator public_flat_rw*/ = 8'd3;
  // verilator lint_off LATCH
  // verilator lint_off UNOPTFLAT
  logic [7:0] cnt = 8'd0;
  always @* if (pr[0]) cnt = cnt + 8'd1;
  // verilator lint_on UNOPTFLAT
  // verilator lint_on LATCH
  assign o = a + cnt;
"""),
    # Nor through a class object, by any handle
    ("every_eval_object", "logic run at every evaluation with effects", """
  class C;
    int cnt;
  endclass
  logic [7:0] pr  /*verilator public_flat_rw*/ = 8'd3;
  C c = new;
  C c2;
  int snap;
  always_comb begin
    c2 = c;
    c2.cnt = c2.cnt + int'(pr);
    snap = c2.cnt;
  end
  assign o = a + 8'(snap);
"""),
    # But it may write a temporary before reading it
    ("every_eval_temp", None, """
  logic [7:0] pr  /*verilator public_flat_rw*/ = 8'd3;
  logic [7:0] t, u;
  always_comb begin
    t = a ^ pr;
    u = t + 8'd1;
  end
  assign o = u;
"""),
    # Nor if it affects the outputs, reading a sampled variable
    ("every_eval_sampled", "logic run at every evaluation reading sampled values", """
  logic [7:0] t  /*verilator public_flat_rd*/;
  always_comb t = $sampled(a);
  assign o = t + 8'd1;
"""),
    # Nor with a port its wrapper's import cannot pass as an integral value
    ("string_port", "ports not passed as integral values", """
  assign o = a + 8'(name.len());
""", "input string name, ", []),
    # Nor for an input whose changes are not detected, so whose readers run at every evaluation
    ("unpacked_input", "logic run at every evaluation with effects", """
  assign o = a;
  always_comb begin
    if (arr[0][0]) $display("[%0t] arr0=%0d", $time, arr[0]);
    assert (arr[1] != 8'd5) else $error("arr1 is 5 at %0t", $time);
  end
""", "input logic [7:0] arr[2], ", []),
    ("forceable_input", "logic run at every evaluation with effects", """
  assign o = f;
  always_comb if (f[0]) $display("[%0t] f=%0d", $time, f);
""", "input logic [7:0] f  /*verilator forceable*/, ", []),
    ("no_ico_change_detect", "logic run at every evaluation with effects", """
  assign o = a;
  always_comb if (a[0]) $display("[%0t] a=%0d", $time, a);
""", "", ["-fno-ico-change-detect"]),
    ("dpi", "unrepeatable combinational logic", """
  import "DPI-C" function int dpic_noise();
  function automatic logic [7:0] noisy(input logic [7:0] v);
    return v + 8'(dpic_noise());
  endfunction
  assign o = noisy(a);
"""),
    ("random", "unrepeatable combinational logic", """
  assign o = a + 8'($random);
"""),
    ("export", "DPI exports", """
  assign o = a;
  export "DPI-C" function get;
  function int get();
    return 1;
  endfunction
"""),
    ("observed", "observed, reactive or postponed logic", """
  logic f;
  assign o = {7'd0, f};
  function void fail();
    f = 1'b1;
  endfunction
  always_comb assert #0 (a != 8'hfe) else fail();
"""),
    ("suspendable", "suspendable logic", """
  logic [7:0] w;
  assign o = w;
  initial forever begin
    @(a);
    w = a;
  end
"""),
)

for case in CASES:
    name, reason, body = case[:3]
    # Extra ports, and flags
    ports, flags = case[3:] if len(case) > 3 else ("", [])
    mdir = test.obj_dir + "/" + name
    os.makedirs(mdir, exist_ok=True)
    filename = test.obj_dir + "/" + name + ".sv"
    header = "module blk (input clk, input [7:0] a, " + ports + "output [7:0] o);"
    test.write_wholefile(filename, header + body + "endmodule\n")
    test.run(logfile=mdir + "/compile.log",
             cmd=[
                 os.environ["VERILATOR_ROOT"] + "/bin/verilator", "--cc", "--timing", "--assert",
                 "--stats", "--lib-create", "blk", "--prefix", "Vblk", "-Mdir", mdir, filename
             ] + flags)
    if reason:
        test.file_grep_not(mdir + "/blk.sv", r'dpi_cache')
        test.file_grep(mdir + "/Vblk__stats.txt",
                       r'library combinational results not reused, ' + reason)
    else:
        test.file_grep(mdir + "/blk.sv", r'/\*verilator dpi_cache\*/')
        test.file_grep_not(mdir + "/Vblk__stats.txt", r'not reused')

test.passes()
