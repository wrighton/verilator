// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Division and modulus by zero give x (IEEE 1800-2023 11.4.3), which as a 2-state
// value is 0 (11.3.4), in a constraint as in procedural code

class DivMod #(
    type T = int
);
  localparam T P3 = 3;
  rand T a, b, q, m, qs, qc, ql, ml, qz, qn, mp;
  T s;
  constraint c_divmod {
    b inside {[0 : 3]};
    q == a / b;
    m == a % b;
    qs == a / s;
    qc == a + s / 3;
    ql == a / 3;
    ml == a % 5;
    qz == a / 0;
    qn == a / -3;
    mp == a % P3;
  }

  task run;
    int randomize_result;
    randomize_result = randomize() with {b == 0;};
    `checkd(randomize_result, 1);
    `checkd(q, a / b);
    `checkd(m, a % b);
    `checkd(qs, a / s);
    `checkd(qc, a + s / 3);
    `checkd(qz, a / s);

    repeat (20) begin
      randomize_result = randomize() with {a inside {[0 : 100]};};
      `checkd(randomize_result, 1);
      `checkd(q, a / b);
      `checkd(m, a % b);
      `checkd(qs, a / s);
      `checkd(qc, a + s / 3);
      `checkd(ql, a / 3);
      `checkd(ml, a % 5);
      `checkd(qn, a / -3);
      `checkd(mp, a % P3);
    end
  endtask
endclass

class Overconstrained;
  rand bit [7:0] b, y;
  constraint c {
    y == 8'd10 / b;
    y == 8'd255;
  }
endclass

module t;
  initial begin
    begin
      DivMod #(bit [6:0]) m_unsigned;
      DivMod #(int) m_signed;
      DivMod #(logic [64:0]) m_wide;
      DivMod #(logic signed [64:0]) m_wide_signed;
      m_unsigned = new;
      m_signed = new;
      m_wide = new;
      m_wide_signed = new;
      m_unsigned.run();
      m_signed.run();
      m_wide.run();
      m_wide_signed.run();
    end

    begin
      Overconstrained m;
      int randomize_result;
      m = new;
      randomize_result = m.randomize();
      `checkd(randomize_result, 0);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
