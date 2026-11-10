// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Static members in inline constraints: those of the object are random
// variables (IEEE 1800-2023 18.4), those of the caller are state values

class Base;
  static rand int unsigned bst;
endclass

class Item extends Base;
  rand int unsigned x;
  static rand int unsigned st;
  static int unsigned lim = 9;

  function void self_run();
    automatic int randomize_result;
    for (int i = 0; i < 20; i++) begin
      randomize_result = randomize() with {
        st inside {[i:i + 1]};
        st != i;
        x < st + lim;
        x > st + 7;
      };
      `checkd(randomize_result, 1);
      `checkd(st, i + 1);
      `checkd(x, i + 9);
    end
  endfunction
endclass

class CallerBase;
  static int unsigned cbst;
endclass

class Caller extends CallerBase;
  static int unsigned cst;

  function void run();
    automatic Item c = new;
    automatic int randomize_result;
    for (int i = 0; i < 20; i++) begin
      cst = 5 + i;
      randomize_result = c.randomize() with {
        x < cst;
        st inside {[cst:cst + 1]};
        bst == st + 1;
        Item::st != cst;
        x < lim;
      };
      `checkd(randomize_result, 1);
      `checkd(c.x < cst && c.x < 9, 1);
      `checkd(Item::st, cst + 1);
      `checkd(Item::bst, cst + 2);
      `checkd(Item::lim, 9);
    end
  endfunction

  static function void srun();
    automatic Item c = new;
    automatic int randomize_result;
    for (int i = 0; i < 20; i++) begin
      cst = 3 + i;
      randomize_result = c.randomize() with {
        x == cst;
        st == x + 1;
      };
      `checkd(randomize_result, 1);
      `checkd(c.x, cst);
      `checkd(Item::st, cst + 1);
    end
  endfunction

  function void std_run();
    automatic int unsigned v;
    automatic int randomize_result;
    for (int i = 0; i < 20; i++) begin
      cst = 2 + i;
      cbst = 3 * i;
      randomize_result = std::randomize(v) with { v inside {[cst - 1:cst]}; v != cst; };
      `checkd(randomize_result, 1);
      `checkd(v, cst - 1);
      randomize_result = std::randomize(v) with { v == cbst + 1; };
      `checkd(randomize_result, 1);
      `checkd(v, 3 * i + 1);
    end
  endfunction
endclass

module t;
  initial begin
    automatic Caller cl = new;
    automatic Item c = new;
    automatic int randomize_result;
    cl.run();
    Caller::srun();
    cl.std_run();
    c.self_run();
    for (int i = 0; i < 20; i++) begin
      randomize_result = c.randomize() with { st inside {[i:i + 1]}; st != i; };
      `checkd(randomize_result, 1);
      `checkd(Item::st, i + 1);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
