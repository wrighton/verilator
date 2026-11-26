// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The result of a signed modulus takes the sign of the first operand
// (IEEE 1800-2023 11.4.3), in a constraint as in procedural code

class ModSigned #(
    type T = int
);
  rand T a, b, r;
  constraint c_rem {
    b != 0;
    r == a % b;
  }

  task check(T va, T vb);
    int randomize_result;
    randomize_result = randomize() with {a == va; b == vb;};
    `checkd(randomize_result, 1);
    `checkd(r, a % b);
  endtask

  task run;
    int randomize_result;
    // Each sign combination of the operands
    check(-7, 2);
    check(7, -2);
    check(-7, -2);
    check(7, 2);

    repeat (20) begin
      randomize_result = randomize();
      `checkd(randomize_result, 1);
      `checkd(r, a % b);
    end

    // A negative dividend has no positive remainder
    randomize_result = randomize() with {a inside {[-8 : -1]}; b inside {[1 : 5]}; r == 1;};
    `checkd(randomize_result, 0);
  endtask
endclass

class ModFixed;
  rand int a, b, r;
  constraint c {
    a == -7;
    b == 2;
    r == a % b;
  }
endclass

class ModUnsat;
  rand int a, b;
  constraint c {
    a inside {[-20 : -1]};
    b inside {[1 : 5]};
    (a % b) == 1;
  }
endclass

module t;
  initial begin
    begin
      ModSigned #(int) m_int;
      ModSigned #(bit signed [6:0]) m_narrow;
      ModSigned #(logic signed [64:0]) m_wide;
      m_int = new;
      m_narrow = new;
      m_wide = new;
      m_int.run();
      m_narrow.run();
      m_wide.run();
    end

    begin
      ModFixed m;
      int randomize_result;
      m = new;
      randomize_result = m.randomize();
      `checkd(randomize_result, 1);
      `checkd(m.r, -1);
    end

    begin
      ModUnsat m;
      int randomize_result;
      m = new;
      randomize_result = m.randomize();
      `checkd(randomize_result, 0);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
