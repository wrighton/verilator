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

  // Constant expressions
  localparam int WB = pkg::W["b"];
  localparam int WMISSING = pkg::W["c"];
  initial begin
    `checkd(WB, 512);
    `checkd(WMISSING, 0);
  end
  if (pkg::W["a"] == 64) begin : g_a
    logic [pkg::W["a"]-2:0] vec;
    initial `checkd($bits(vec), 63);
  end else begin : g_not_a
    initial `stop;
  end

  // A missing key reads the default
  localparam bit [6:0] I[logic [14:0]] = '{15'h7fff: 7'h55, 15'h1: 7'h2a, default: 7'h3};
  initial begin
    for (int k = 0; k < 3; ++k) `checkh(I[15'(k)], (k == 1) ? 7'h2a : 7'h3);
    `checkh(I[15'h7fff], 7'h55);
    `checkd(I.num(), 2);
  end
  localparam bit [6:0] IMAX = I[15'h7fff];
  localparam bit [6:0] IMISSING = I[15'h2];
  initial begin
    `checkh(IMAX, 7'h55);
    `checkh(IMISSING, 7'h3);
  end

  // Without a default, a missing key reads the default value of the element type
  typedef string names_t[int];
  localparam names_t S = '{-1: "minus", 5: "five"};
  initial begin
    for (int k = 4; k < 7; ++k) `checks(S[k], (k == 5) ? "five" : "");
    `checks(S[-1], "minus");
  end
  localparam string SFIVE = S[5];
  localparam string SMISSING = S[6];
  initial begin
    `checks(SFIVE, "five");
    `checks(SMISSING, "");
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
  typedef struct {
    bit b;
  } bkey_t;
  localparam int BK[bkey_t] = '{bkey_t'{1'b0}: 11, default: 77};
  localparam bkey_t BKX = '{1'bx};
  localparam int BKNAMED = BK[BKX];
  localparam int BKINLINE = BK[bkey_t'{1'bx}];
  initial begin
    `checkd(BKNAMED, 11);
    `checkd(BKINLINE, 11);
  end
  // A key converts to a 2-state key type, but is an invalid index of a 4-state one if it has X
  typedef struct packed {
    bit hi;
    bit lo;
  } pkey_t;
  localparam int PK[pkey_t] = '{pkey_t'{1'b0, 1'b1}: 11, default: 77};
  localparam int PKINLINE = PK[pkey_t'{1'bx, 1'b1}];
  localparam int BV[bit [6:0]] = '{7'h01: 11, default: 77};
  localparam int BVX = BV[7'bx00_0001];
  localparam int LV[logic [6:0]] = '{7'h01: 11, default: 77};
  localparam int LVX = LV[7'bx00_0001];
  initial begin
    `checkd(PKINLINE, 11);
    `checkd(BVX, 11);
    `checkd(LVX, 77);
  end
  // A key with a real value matches an equal real, and an array key each element
  typedef struct {
    real r;
    int n;
  } rkey_t;
  localparam int RK[rkey_t] = '{rkey_t'{0.0, 1}: 11, rkey_t'{1.5, 2}: 22, default: 77};
  localparam int RKNEG = RK[rkey_t'{-0.0, 1}];
  localparam int RKHIT = RK[rkey_t'{1.5, 2}];
  localparam int RKMISS = RK[rkey_t'{1.5, 1}];
  typedef int akey_t[2];
  localparam int AK[akey_t] = '{'{1, 2}: 11, '{3, 4}: 22, default: 77};
  localparam akey_t AK34 = '{3, 4};
  localparam int AKHIT = AK[AK34];
  localparam int AKMISS = AK[akey_t'{4, 3}];
  // A NaN equals no real, so a NaN key matches no entry
  localparam real NAN = $bitstoreal(64'h7ff8_0000_0000_0000);
  localparam int RKN[rkey_t] = '{rkey_t'{NAN, 1}: 11, rkey_t'{1.5, 1}: 22, default: 77};
  localparam int RKNAN = RKN[rkey_t'{NAN, 1}];
  localparam int RKNANOTHER = RKN[rkey_t'{1.5, 1}];
  initial begin
    `checkd(RKNEG, 11);
    `checkd(RKHIT, 22);
    `checkd(RKMISS, 77);
    `checkd(RKNAN, 77);
    `checkd(RKNANOTHER, 22);
    `checkd(AKHIT, 22);
    `checkd(AKMISS, 77);
  end
  localparam st_t K45 = '{4, 5};
  localparam int SVA = SV[K45].a;
  initial `checkd(SVA, 6);

  localparam int C[string] = pkg::W;
  initial `checkd(C["a"], 64);

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

  // A value assigned to a 2-state element loses its X bits
  localparam bit B[int] = '{0: 1'bx, default: 1'bx};
  localparam bit BHIT = B[0] === 1'b0;
  localparam bit BMISSING = B[1] === 1'b0;
  initial begin
    `checkd(BHIT, 1'b1);
    `checkd(BMISSING, 1'b1);
  end

  localparam bit [7:0] WIDE[bit [64:0]] = '{65'h1_0000_0000_0000_0003: 8'h5a, 65'h3: 8'ha5};
  localparam bit [7:0] WIDEHI = WIDE[65'h1_0000_0000_0000_0003];
  localparam bit [7:0] WIDELO = WIDE[65'h3];
  initial begin
    `checkh(WIDEHI, 8'h5a);
    `checkh(WIDELO, 8'ha5);
  end

  initial begin
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
