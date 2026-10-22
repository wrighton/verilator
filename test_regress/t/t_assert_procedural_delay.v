// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// IEEE 1800-2023 16.14.6: procedural concurrent assertions with cycle delays
// take the clock inferred from the always; each is compared with the same
// assertion explicitly clocked at module scope.
module t (
  input clk
);
  int unsigned crc = 32'h1;
  bit a, b, c;
  int cyc = 0;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[30:0], crc[31] ^ crc[21] ^ crc[1] ^ crc[0]};
    a <= crc[0];
    b <= crc[2];
    c <= crc[5];
    if (cyc == 40) $finish;
  end

  int fails1 = 0, fails2 = 0, passes3 = 0, fails3 = 0;
  always @(posedge clk) begin
    assert property (a |-> ##1 b)
    else fails1++;
    assert property (a ##1 b)
    else fails2++;
    assert property (a ##1 b |-> c) passes3++;
    else fails3++;
  end

  int fails4 = 0;
  always_ff @(negedge clk) begin
    assert property (a |=> b ##[1:2] c)
    else fails4++;
  end

  int ref_fails1 = 0, ref_fails2 = 0, ref_passes3 = 0, ref_fails3 = 0, ref_fails4 = 0;
  assert property (@(posedge clk) a |-> ##1 b)
  else ref_fails1++;
  assert property (@(posedge clk) a ##1 b)
  else ref_fails2++;
  assert property (@(posedge clk) a ##1 b |-> c) ref_passes3++;
  else ref_fails3++;
  assert property (@(negedge clk) a |=> b ##[1:2] c)
  else ref_fails4++;

  // Counts read in final (Postponed) to avoid same-timestep races.
  final begin
    `checkd(fails1, ref_fails1);
    `checkd(fails2, ref_fails2);
    `checkd(passes3, ref_passes3);
    `checkd(fails3, ref_fails3);
    `checkd(fails4, ref_fails4);
    `checkd(ref_fails1, 12);
    `checkd(ref_fails2, 26);
    `checkd(ref_passes3, 37);
    `checkd(ref_fails3, 4);
    `checkd(ref_fails4, 13);
    $write("*-* All Finished *-*\n");
  end
endmodule
