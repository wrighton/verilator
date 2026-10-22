// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// nexttime and s_nexttime (IEEE 1800-2023 16.12.10), each compared with the
// equivalent assertion written out
module t (
  input clk
);
  int unsigned crc = 32'h1;
  logic a, b, c;
  int cyc = 0;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[30:0], crc[31] ^ crc[21] ^ crc[1] ^ crc[0]};
    a <= crc[0];
    b <= crc[5];
    c <= crc[11];
    if (cyc == 40) $finish;
  end

  int fails_next = 0, ref_fails_next = 0;
  assert property (@(posedge clk) a |-> nexttime b)
  else fails_next++;
  assert property (@(posedge clk) a |=> b)
  else ref_fails_next++;

  int fails_snext = 0;
  assert property (@(posedge clk) a |-> s_nexttime b)
  else fails_snext++;

  int fails_next2 = 0, ref_fails_next2 = 0;
  assert property (@(posedge clk) a |-> nexttime [2] b)
  else fails_next2++;
  assert property (@(posedge clk) a |-> ##2 b)
  else ref_fails_next2++;

  int fails_next0 = 0, ref_fails_next0 = 0;
  assert property (@(posedge clk) a |-> nexttime [0] b)
  else fails_next0++;
  assert property (@(posedge clk) a |-> b)
  else ref_fails_next0++;

  int fails_until = 0, ref_fails_until = 0;
  assert property (@(posedge clk) $rose(a) |-> nexttime (!b until_with c))
  else fails_until++;
  assert property (@(posedge clk) $rose(a) |=> (!b until_with c))
  else ref_fails_until++;

  int fails_top = 0, ref_fails_top = 0;
  assert property (@(posedge clk) nexttime c)
  else fails_top++;
  assert property (@(posedge clk) 1'b1 |=> c)
  else ref_fails_top++;

  // Counts read in final (Postponed) to avoid same-timestep races.
  final begin
    `checkd(fails_next, ref_fails_next);
    `checkd(fails_snext, ref_fails_next);
    `checkd(fails_next2, ref_fails_next2);
    `checkd(fails_next0, ref_fails_next0);
    `checkd(fails_until, ref_fails_until);
    `checkd(fails_top, ref_fails_top);
    `checkd(ref_fails_next, 13);
    `checkd(ref_fails_next2, 7);
    `checkd(ref_fails_next0, 14);
    `checkd(ref_fails_until, 10);
    `checkd(ref_fails_top, 23);
    $write("*-* All Finished *-*\n");
  end
endmodule
