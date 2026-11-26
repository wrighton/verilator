// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// 'throughout' over a 'within' long enough for the state signals of its Link-only vertices
// to be computed in temporaries, against a model of IEEE 1800-2023 16.9.9 and 16.9.10.
// Each attempt of the cover matches at most once, at its fixed end.

module t (
    input clk
);
  localparam int N = 40;
  localparam int END = 600;

  int cyc = 0;
  bit [63:0] crc = 64'h5aa5_0f0f_3c3c_9696;
  wire a = crc[0];
  wire b = crc[1];
  wire c = crc[2];
  wire e = !(crc[4] && crc[5] && crc[6] && crc[7] && crc[8]);
  // Low with e, so that no attempt ends where e is low
  wire d = crc[3] && e;
  // Values of the previous cycles, the last one at [0]
  logic [N-1:0] ha = '0, hb = '0, hc = '0, he = '0;

  int n_pass = 0;
  int n_pass_exp = 0;

  cover property (@(posedge clk) disable iff (cyc > END)
                  a ##0 (e throughout ((b ##1 c) within (1'b1 ##N d)))) ++n_pass;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    ha <= {ha[N-2:0], a};
    hb <= {hb[N-2:0], b};
    hc <= {hc[N-2:0], c};
    he <= {he[N-2:0], e};
    // The attempt started N cycles ago, with a, ends now
    if (cyc <= END && cyc >= N && ha[N-1] && d && e && &he && |(hb & {hc[N-2:0], c})) begin
      ++n_pass_exp;
    end
    if (cyc == END + 2) begin
      `checkd(n_pass, n_pass_exp);
      if (n_pass == 0) `stop;
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
