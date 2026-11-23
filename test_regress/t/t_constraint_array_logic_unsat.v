// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class HardArrayCore;
  logic [3:0] a[2] = '{4'h3, 4'h5};
  rand int unsigned idx;
  rand bit [3:0] v;
  constraint c_idx {idx == 1;}
  constraint c_array {v == a[idx];}
  constraint c_conflict {v != 5;}
endclass

// A soft array constraint does not belong to the unsatisfiable hard core.
class SoftArrayCore;
  logic [3:0] a[2] = '{4'h3, 4'h5};
  rand int unsigned soft_idx;
  rand bit [3:0] soft_v;
  constraint c_zero {soft_v == 0;}
  constraint c_one {soft_v == 1;}
  constraint c_soft {soft soft_v == a[soft_idx];}
endclass

module t;
  initial begin
    automatic HardArrayCore hard_obj = new;
    automatic SoftArrayCore soft_obj = new;
    int ok;
    // Each hard core is minimally unsatisfiable.
    ok = hard_obj.randomize();
    `checkd(ok, 0);
    `checkd(hard_obj.a[0], 3);
    `checkd(hard_obj.a[1], 5);
    ok = soft_obj.randomize();
    `checkd(ok, 0);
    `checkd(soft_obj.a[0], 3);
    `checkd(soft_obj.a[1], 5);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
