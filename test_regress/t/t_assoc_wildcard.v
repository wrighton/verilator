// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2019 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);

  integer cyc = 0;

  integer i;

  localparam string KEY_S = "PPP";
  localparam bit [23:0] KEY_I = 24'h515151;  // "QQQ"
  typedef enum bit [23:0] {
    KEY_E = 24'h525252  // "RRR"
  } key_e;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    begin
      // Wildcard
      typedef string dict_t [*];
      static string a [*] = '{default: "nope", "BBBBB": "fooing", 23'h434343: "baring"};
      static dict_t b = '{default: "nope", "BBBBB": "fooing", 23'h434343: "baring"};
      int k;
      string v;

      v = b["CCC"];
      `checks(v, "baring");
      v = b["BBBBB"];
      `checks(v, "fooing");

      v = a["CCC"];
      `checks(v, "baring");
      v = a["BBBBB"];
      `checks(v, "fooing");

      a[32'd1234] = "fooed";
      a[4'd3] = "bared";
      a[79'h4141] = "bazed";
      i = a.num();
      `checkh(i, 5);
      i = a.size();
      `checkh(i, 5);
      v = a[39'd1234];
      `checks(v, "fooed");
      v = a["AA"];
      `checks(v, "bazed");
      v = a[4'd3];
      `checks(v, "bared");
      i = a.exists("baz");
      `checkh(i, 0);
      i = a.exists(4'd3);
      `checkh(i, 1);
      a.delete(4'd3);
      i = a.size();
      `checkh(i, 4);
    end
    begin
      // Wildcard with parameter and enum keys
      static string p [*] = '{default: "nope", KEY_S: "sparam", KEY_I: "iparam", KEY_E: "enum"};
      string v;

      v = p["PPP"];
      `checks(v, "sparam");
      v = p["QQQ"];
      `checks(v, "iparam");
      v = p["RRR"];
      `checks(v, "enum");
      v = p["KEY_S"];  // Keyed by the value, not the name
      `checks(v, "nope");

      // Without a default, and empty
      p = '{"x": "xed"};
      v = p["x"];
      `checks(v, "xed");
      i = p.size();
      `checkh(i, 1);
      p = '{};
      i = p.size();
      `checkh(i, 0);
    end

    begin
      // Keys with zero bytes are distinct, and a value is the same key at any width
      static int z[*] = '{0: 10, 1: 11, 256: 12, 65'h1_0000_0000_0000_0000: 13};
      int k;
      string sk;
      k = cyc + 256;
      sk = "\001";
      `checkh(z[sk], 11);
      `checkh(z.num(), 4);
      `checkh(z[k], 12);
      `checkh(z[k - 255], 11);
      `checkh(z[8'd1], 11);
      `checkh(z[0], 10);
      `checkh(z[1'b0], 10);
      `checkh(z[""], 10);
      z[k + 1] = 14;
      z[{k, 8'd0}] = 15;
      z[65'h1_0000_0000_0000_0000] = 16;
      z[{k, 64'd0}] = 17;
      `checkh(z.num(), 7);
      `checkh(z[257], 14);
      `checkh(z[32'h10000], 15);
      `checkh(z[65'h1_0000_0000_0000_0000], 16);
      `checkh(z[96'h100_0000_0000_0000_0000], 17);
      `checkh(z[k - 256], 10);
      `checkh(z.exists(k * 256), 1);
      `checkh(z.exists(k * 512), 0);
      z.delete(k);
      `checkh(z.exists(256), 0);
      `checkh(z.num(), 6);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
