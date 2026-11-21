// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Michael Wrighton
// SPDX-License-Identifier: CC0-1.0

// Parameters of associative array, dynamic array and queue type with assignment pattern values

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkr(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got=%f exp=%f\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

package pkg;
  parameter int W[string] = '{"a": 64, "b": 512};
endpackage

// An aggregate parameter is overridden as a whole (IEEE 1800-2023 6.20.2)
module sub #(
    parameter int M[string] = '{"x": 1},
    parameter int N[$] = '{2},
    parameter int EXPM = 1,
    parameter int EXPN = 2
) ();
  initial begin
    `checkd(M["x"], EXPM);
    `checkd(N[$], EXPN);
  end
endmodule

module t;
  sub u_default ();
  sub #(.M('{"x": 33, "y": 4}), .N('{5, 6}), .EXPM(33), .EXPN(6)) u_override ();

  initial begin
    string key;
    `checkd(pkg::W["b"], 512);
    key = "a";
    `checkd(pkg::W[key], 64);
    `checkd(pkg::W.size(), 2);
  end

  // A missing key reads the default
  localparam bit [6:0] I[logic [14:0]] = '{15'h7fff: 7'h55, 15'h1: 7'h2a, default: 7'h3};
  initial begin
    for (int k = 0; k < 3; ++k) `checkh(I[15'(k)], (k == 1) ? 7'h2a : 7'h3);
    `checkh(I[15'h7fff], 7'h55);
    `checkd(I.num(), 2);
  end
  // Without a default, a missing key reads the default value of the element type
  typedef string names_t[int];
  localparam names_t S = '{-1: "minus", 5: "five"};
  initial begin
    for (int k = 4; k < 7; ++k) `checks(S[k], (k == 5) ? "five" : "");
    `checks(S[-1], "minus");
  end
  localparam real R[*] = '{8'h3: 1.5, default: 0.25};
  initial begin
    for (int k = 2; k < 5; ++k) `checkr(R[8'(k)], (k == 3) ? 1.5 : 0.25);
  end

  typedef struct {
    int a;
    bit [30:0] b;
  } st_t;
  localparam st_t SV[st_t] = '{'{1, 2}: '{3, 31'h7fff_fffe}, '{4, 5}: '{6, 7}};
  initial begin
    st_t k;
    k = '{4, 5};
    `checkd(SV[k].a, 6);
    k.a = 1;
    k.b = 2;
    `checkh(SV[k].b, 31'h7fff_fffe);
  end
  localparam int D[] = '{1, 2, 3};
  localparam int DK[] = '{2: 9, default: 8};
  localparam int Q[$:7] = '{4, 5};
  initial begin
    `checkd(D.size(), 3);
    foreach (D[i]) `checkd(D[i], i + 1);
    `checkd(DK.size(), 3);
    foreach (DK[i]) `checkd(DK[i], (i == 2) ? 9 : 8);
    `checkd(Q.size(), 2);
    `checkd(Q[$], 5);
  end

  initial begin
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
