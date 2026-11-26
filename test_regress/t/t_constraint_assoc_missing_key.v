// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Randomization creates no associative array key, and an element whose key does not exist reads
// as the array's default (IEEE 1800-2023 7.8.6, 18.4)

class StrKey;
  rand int aa[string];
  constraint c {aa["k"] == 77;}
endclass

class StrKeyZero;
  rand int aa[string];
  constraint c {aa["k"] == 0;}
endclass

class IntKey;
  rand bit [7:0] aa[int];
  int key = 5;
  constraint c {
    aa[3] == 8'h11;
    aa[key] == 8'h22;
  }
endclass

class DefaultKey;
  rand bit [6:0] ai[int];
  rand int astr[string];
  bit [6:0] want_i = 7'd53;
  int want_s = 9;
  constraint c {
    ai[4] == want_i;
    astr["m"] == want_s;
  }
  function new();
    ai = '{default: 7'd53};
    astr = '{default: 9};
  endfunction
endclass

class Plain;
  rand bit [7:0] x;
endclass

module t;
  int randomize_result;

  initial begin
    // Test: a constraint on a missing string key fails and creates nothing
    begin
      automatic StrKey o = new;
      randomize_result = o.randomize();
      `checkd(randomize_result, 0);
      `checkd(o.aa.num(), 0);
      o.aa["k"] = 5;
      randomize_result = o.randomize();
      `checkd(randomize_result, 1);
      `checkd(o.aa["k"], 77);
      `checkd(o.aa.num(), 1);
    end

    // Test: a missing key constrained to its default succeeds and creates nothing
    begin
      automatic StrKeyZero o = new;
      randomize_result = o.randomize();
      `checkd(randomize_result, 1);
      `checkd(o.aa.num(), 0);
    end

    // Test: integer keys, constant and state, all of which must exist
    begin
      automatic IntKey o = new;
      randomize_result = o.randomize();
      `checkd(randomize_result, 0);
      `checkd(o.aa.num(), 0);
      o.aa[3] = 8'h0;
      randomize_result = o.randomize();
      `checkd(randomize_result, 0);
      `checkd(o.aa.num(), 1);
      o.aa[5] = 8'h0;
      randomize_result = o.randomize();
      `checkd(randomize_result, 1);
      `checkd(o.aa[3], 8'h11);
      `checkd(o.aa[5], 8'h22);
      `checkd(o.aa.num(), 2);
    end

    // Test: a missing key reads the array's explicit default
    begin
      automatic DefaultKey o = new;
      randomize_result = o.randomize();
      `checkd(randomize_result, 1);
      `checkd(o.ai.num(), 0);
      `checkd(o.astr.num(), 0);
      o.want_i = 7'd0;
      randomize_result = o.randomize();
      `checkd(randomize_result, 0);
      o.want_i = 7'd53;
      o.want_s = 0;
      randomize_result = o.randomize();
      `checkd(randomize_result, 0);
    end

    // Test: an inline constraint on a missing key fails
    begin
      automatic StrKeyZero o = new;
      automatic Plain plain = new;
      randomize_result = o.randomize() with {aa["q"] == 1;};
      `checkd(randomize_result, 0);
      `checkd(o.aa.num(), 0);
      // An unrelated randomization still succeeds afterwards
      randomize_result = plain.randomize() with {x == 8'h5a;};
      `checkd(randomize_result, 1);
      `checkd(plain.x, 8'h5a);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
