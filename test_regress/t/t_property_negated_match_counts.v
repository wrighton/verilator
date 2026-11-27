// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// A negated assertion fails on each match of its operand and passes once the operand fails
// (IEEE 1800-2023 16.12.3), also when the operand ends without a final condition, against a
// model of each attempt

module t (
    input clk
);
  localparam int END = 300;

  int cyc = 0;
  bit [63:0] crc = 64'h5aef_0c8d_d70a_4497;
  wire a = crc[0] | crc[3];
  wire b = crc[5] | crc[9];
  wire c = crc[13] | crc[17];
  wire d = crc[21] | crc[25];
  bit ha[END + 3], hb[END + 3], hc[END + 3], hd[END + 3];

  int n_pass1 = 0, n_fail1 = 0, n_pass2 = 0, n_fail2 = 0;

  // The operand ends in a repetition, with no final condition
  assert property (@(posedge clk) disable iff (cyc > END) not (a ##1 b [*2])) ++n_pass1;
  else ++n_fail1;
  // The operand is an 'or' of sequences of one length
  assert property (@(posedge clk) disable iff (cyc > END) not ((a ##1 b) or (c ##1 d)))
    ++n_pass2;
  else ++n_fail2;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc <= END + 2) begin
      ha[cyc] = a;
      hb[cyc] = b;
      hc[cyc] = c;
      hd[cyc] = d;
    end
    if (cyc == END + 3) begin
      automatic int p1 = 0, f1 = 0, p2 = 0, f2 = 0;
      // Count the passes and failures of attempts started on cycle s on the cycles they
      // resolve, up to END
      for (int s = 0; s <= END; ++s) begin
        if (ha[s] && hb[s+1] && hb[s+2]) begin
          if (s + 2 <= END) ++f1;
        end
        else if (!ha[s]) ++p1;
        else if (!hb[s+1]) begin
          if (s + 1 <= END) ++p1;
        end
        else if (s + 2 <= END) ++p1;
        if (!ha[s] && !hc[s]) ++p2;
        else if (s + 1 <= END) begin
          if ((ha[s] && hb[s+1]) || (hc[s] && hd[s+1])) ++f2;
          else ++p2;
        end
      end
      `checkd(n_pass1, p1);
      `checkd(n_fail1, f1);
      `checkd(n_pass2, p2);
      `checkd(n_fail2, f2);
      if (p1 == 0 || f1 == 0 || p2 == 0 || f2 == 0) `stop;
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
