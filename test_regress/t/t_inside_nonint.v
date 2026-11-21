// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2023 Antmicro Ltd
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

function bit check_string(string s);
  if (s inside {"RW", "WO"}) return 1'b1;
  return 1'b0;
endfunction

function bit check_double(real d);
  if (d inside {0.0, 2.5}) return 1'b1;
  return 1'b0;
endfunction

function bit check_string_range(string s);
  return s inside {["a rock":"hard place"]};
endfunction

function bit check_double_range(real d);
  case (d) inside
    [1.0:2.0], [3.0:4.0]: return 1'b1;
    default: return 1'b0;
  endcase
endfunction

function bit check_signed_range(int i);
  case (i) inside
    [-5:5]: return i inside {[-5:5]};
    default: return 1'b0;
  endcase
endfunction

module t;
  typedef real real_t;
  typedef string string_t;

  initial begin
    begin
      // Ranges of nonintegral values, at runtime
      `checkd(check_string_range("a rock"), 1'b1);
      `checkd(check_string_range("b"), 1'b1);
      `checkd(check_string_range("hard place"), 1'b1);
      `checkd(check_string_range("a"), 1'b0);
      `checkd(check_string_range("i"), 1'b0);
      `checkd(check_double_range(1.0), 1'b1);
      `checkd(check_double_range(1.5), 1'b1);
      `checkd(check_double_range(2.0), 1'b1);
      `checkd(check_double_range(3.5), 1'b1);
      `checkd(check_double_range(2.5), 1'b0);
    end
    begin
      // Ranges of nonintegral values, known at compile time
      real r;
      string s;
      real_t tr;
      string_t ts;
      r = 1.5;
      s = "bb";
      tr = 2.25;
      ts = "bb";
      `checkd(r inside {[1.0:2.0]}, 1'b1);
      `checkd(r inside {[2:3]}, 1'b0);
      `checkd(s inside {["a":"c"]}, 1'b1);
      `checkd(s inside {["c":"d"]}, 1'b0);
      `checkd(tr inside {[1.1:2.1]}, 1'b0);
      `checkd(tr inside {[2.2:2.3]}, 1'b1);
      `checkd(ts inside {["a":"c"]}, 1'b1);
      `checkd(ts inside {["c":"d"]}, 1'b0);
    end
    begin
      // Ranges with negative bounds compare signed
      int count;
      count = 0;
      for (int i = -7; i <= 7; ++i) count += check_signed_range(i);
      `checkd(count, 11);
      `checkd(check_signed_range(-3), 1'b1);
      `checkd(check_signed_range(-6), 1'b0);
    end

    if (!check_string("WO")) $stop;
    if (!check_string("RW")) $stop;
    if (check_string("ABC")) $stop;
    if (!check_double(0.0)) $stop;
    if (!check_double(2.5)) $stop;
    if (check_double(1.0)) $stop;

    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
