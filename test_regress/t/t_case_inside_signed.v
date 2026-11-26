// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// verilator lint_off WIDTH
module t;

  // Each item matches as its own 'inside' operation (IEEE 1800-2023 12.5.4)
  function automatic int in_range(input int i);
    case (i) inside
      [-5 : 5]: return 1;
      default: return 0;
    endcase
  endfunction

  function automatic int mixed(input bit signed [7:0] v);
    case (v) inside
      [9'd0 : 9'd250]: return 1;
      [-8'sd10 : 8'sd10], 9'd300: return 2;
      default: return 0;
    endcase
  endfunction

  function automatic int values(input bit signed [7:0] v, input bit [8:0] u);
    case (v) inside
      9'b0_1111_10??: return 1;
      u: return 2;
      -8'sd1, 9'h1ff: return 3;
      default: return 0;
    endcase
  endfunction

  int calls = 0;
  function automatic bit signed [7:0] next_value(input bit signed [7:0] value);
    ++calls;
    return value;
  endfunction

  initial begin
    begin
      int count;
      count = 0;
      for (int i = -7; i <= 7; ++i) count += in_range(i);
      `checkd(count, 11);
    end
    begin
      // A signed byte compares unsigned with 9-bit unsigned items, so -5 is 251
      `checkd(mixed(-5), 2);
      `checkd(mixed(5), 1);
      `checkd(mixed(-11), 1);
      `checkd(mixed(-128), 1);
      `checkd(mixed(127), 1);
      `checkd(values(-5, 0), 1);
      `checkd(values(-3, 9'd253), 2);
      `checkd(values(-3, 9'h1fd), 0);
      `checkd(values(-1, 0), 3);
      `checkd(values(7, 0), 0);
    end
    begin
      // The case expression is evaluated once
      int r;
      case (next_value(-3)) inside
        [9'd0 : 9'd250]: r = 1;
        [-8'sd5 : 8'sd5]: r = 2;
        default: r = 0;
      endcase
      `checkd(r, 2);
      `checkd(calls, 1);
    end
    begin
      bit signed [7:0] v;
      int r;
      for (int i = -8; i < 8; ++i) begin
        v = 8'(i);
        unique case (v) inside
          [9'd0 : 9'd127], 9'd300: r = 1;
          [-8'sd10 : -8'sd1]: r = 2;
        endcase
        `checkd(r, i < 0 ? 2 : 1);
      end
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
