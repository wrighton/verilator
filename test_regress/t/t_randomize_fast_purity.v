// DESCRIPTION: Verilator: Unsupported native bound dependencies retain the solver
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Michael Wrighton
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

class HiddenState;
  static rand bit [6:0] limit;
endclass
function automatic longint unsigned late_rand_bound();
  longint unsigned scratch;
  scratch = 0;
  late_rand_bound = 64'(HiddenState::limit) + scratch;
endfunction

module t;
  initial begin
    bit [6:0] value;
    int result;
    HiddenState::limit = 7;
    value = 77;
    result = std::randomize(
        value
    ) with {
      value inside {[7'd0 : 7'd7]};
      soft 64'(value) dist {[64'd0 : late_rand_bound()] :/ 1};
    };
    `checkd(result, 0);
    `checkd(value, 77);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule

import "DPI-C" pure function longint unsigned fast_purity_limit();
function automatic longint unsigned late_dpi_bound();
  longint unsigned scratch;
  scratch = 0;
  late_dpi_bound = fast_purity_limit() + scratch;
endfunction

module dpi_t;
  initial begin
    bit [6:0] value;
    int result;
    value = 77;
    result = std::randomize(
        value
    ) with {
      value inside {[7'd0 : 7'd7]};
      soft 64'(value) dist {[64'd0 : late_dpi_bound()] :/ 1};
    };
    `checkd(result, 0);
    `checkd(value, 77);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule

function automatic longint unsigned input_bound(longint unsigned value);
  input_bound = value;
endfunction
module arg_t;
  initial begin
    int unsigned value;
    int result;
    value = 77;
    result = std::randomize(
        value
    ) with {
      value inside {[0 : 7]};
      soft 64'(value) dist {[64'd0 : input_bound(64'(value))] :/ 1};
    };
    `checkd(result, 0);
    `checkd(value, 77);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule

function automatic int mixed_bound_pick(ref int value, input longint unsigned hi);
  return std::randomize(
      value
  ) with {
    value inside {-2, -1, 0, 1, 2};
    soft longint'(value) dist {[64'sd0 : hi] :/ 1};
  };
endfunction
module mixed_t;
  initial begin
    int value;
    int result;
    value  = 77;
    result = mixed_bound_pick(value, 64'h8000_0000_0000_0001);
    `checkd(result, 0);
    `checkd(value, 77);
    result = mixed_bound_pick(value, 64'hffff_ffff_ffff_ffff);
    `checkd(result, 0);
    `checkd(value, 77);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
