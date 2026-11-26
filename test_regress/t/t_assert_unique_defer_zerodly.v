// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Violations of unique, unique0 and priority checks settled after a #0 delay, in the Inactive
// region of the time step, are not reported (IEEE 1800-2023 12.4.2.1, 12.5.3.1). Any report fails.
module t;
  // IEEE 1800-2023 12.4.2.1 and 12.5.3.1 examples
  logic a = 0, not_a = 1, z;
  logic [1:0] sel = 2'b01;
  logic y;
  always_comb begin : a1
    u1 : unique if (a) z = 1'b1;
    else if (not_a) z = 1'b0;
  end
  always_comb begin : a2
    unique case (1'b1)
      sel[0]: y = 1'b0;
      sel[1]: y = 1'b1;
    endcase
  end
  initial begin
    #1;
    a = 1;
    sel = 2'b11;
    #0;
    not_a = 0;
    sel = 2'b10;
    #1;
    `checkh(z, 1'b1);
    `checkh(y, 1'b1);
  end

  // IEEE 1800-2023 12.4.2.1 loop example
  logic [2:0] loop_a = 3'b000, loop_not_a = 3'b111, loop_z;
  always_comb begin : loop_glitch
    for (int j = 0; j < 3; j++)
      unique if (loop_a[j]) loop_z[j] = 1'b1;
      else if (loop_not_a[j]) loop_z[j] = 1'b0;
  end
  initial begin
    #1;
    loop_a = 3'b101;
    #0;
    loop_not_a = 3'b010;
    #1;
    `checkh(loop_z, 3'b101);
  end

  logic [1:0] pc_sel = 2'b01;
  logic pc_y;
  always_comb begin : priority_glitch
    pc_y = 1'b0;
    priority case (1'b1)
      pc_sel[0]: pc_y = 1'b0;
      pc_sel[1]: pc_y = 1'b1;
    endcase
  end
  initial begin
    #1;
    pc_sel = 2'b00;
    #0;
    pc_sel = 2'b10;
    #1;
    `checkh(pc_y, 1'b1);
  end

  initial begin
    #5;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
