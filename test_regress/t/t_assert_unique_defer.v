// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Violations of unique, unique0 and priority checks that do not persist to the Observed region
// of their time step are not reported (IEEE 1800-2023 12.4.2.1, 12.5.3.1). Any report fails.
// The settling values are nonblocking assignments, made in the NBA region of the active region
// set (IEEE 1800-2023 4.4.1).
module t;
  // IEEE 1800-2023 12.4.2.1 example: an always_comb re-executed in the same time step flushes
  // the overlap it saw before
  logic if_a = 0, if_not_a = 1, if_z;
  always_comb begin : if_glitch
    u1 : unique if (if_a) if_z = 1'b1;
    else if (if_not_a) if_z = 1'b0;
  end
  initial begin
    #1;
    if_a = 1;
    if_not_a <= 0;
    #1;
    `checkh(if_z, 1'b1);
  end

  // IEEE 1800-2023 12.4.2.1 loop example: every pending report of the loop is flushed
  logic [2:0] loop_a = 3'b000, loop_not_a = 3'b111, loop_z;
  always_comb begin : loop_glitch
    for (int j = 0; j < 3; j++)
      unique if (loop_a[j]) loop_z[j] = 1'b1;
      else if (loop_not_a[j]) loop_z[j] = 1'b0;
  end
  initial begin
    #1;
    loop_a = 3'b101;
    loop_not_a <= 3'b010;
    #1;
    `checkh(loop_z, 3'b101);
  end

  logic u0_a = 0, u0_b = 1, u0_z;
  always_comb begin : unique0_if_glitch
    u0_z = 1'b0;
    unique0 if (u0_a) u0_z = 1'b1;
    else if (u0_b) u0_z = 1'b0;
  end
  initial begin
    #1;
    u0_a = 1;
    u0_b <= 0;
    #1;
    `checkh(u0_z, 1'b1);
  end

  // IEEE 1800-2023 12.5.3.1 example, multiple matches
  logic [1:0] uc_sel = 2'b01;
  logic uc_y;
  always_comb begin : unique_case_glitch
    unique case (1'b1)
      uc_sel[0]: uc_y = 1'b0;
      uc_sel[1]: uc_y = 1'b1;
    endcase
  end
  initial begin
    #1;
    uc_sel = 2'b11;
    uc_sel <= 2'b10;
    #1;
    `checkh(uc_y, 1'b1);
  end

  // No match
  logic [30:0] none_v = 31'd1;
  logic [1:0] none_y;
  always_comb begin : unique_case_none_glitch
    unique case (none_v)
      31'd1: none_y = 2'd1;
      31'd2: none_y = 2'd2;
    endcase
  end
  initial begin
    #1;
    none_v = 31'd99;
    none_v <= 31'd2;
    #1;
    `checkh(none_y, 2'd2);
  end

  logic [6:0] u0c_v = 7'd1;
  logic [1:0] u0c_y;
  always_comb begin : unique0_case_glitch
    u0c_y = 2'd0;
    unique0 case (u0c_v) inside
      [7'd1 : 7'd5]: u0c_y = 2'd1;
      [7'd4 : 7'd9]: u0c_y = 2'd2;
    endcase
  end
  initial begin
    #1;
    u0c_v = 7'd4;
    u0c_v <= 7'd8;
    #1;
    `checkh(u0c_y, 2'd2);
  end

  logic [1:0] pc_sel = 2'b01;
  logic pc_y;
  always_comb begin : priority_case_glitch
    pc_y = 1'b0;
    priority case (1'b1)
      pc_sel[0]: pc_y = 1'b0;
      pc_sel[1]: pc_y = 1'b1;
    endcase
  end
  initial begin
    #1;
    pc_sel = 2'b00;
    pc_sel <= 2'b10;
    #1;
    `checkh(pc_y, 1'b1);
  end

  // An always procedure resumed from its event control flushes its pending reports
  logic [1:0] at_sel = 2'b01;
  logic at_y;
  always @(at_sel) begin : always_resume
    unique case (1'b1)
      at_sel[0]: at_y = 1'b0;
      at_sel[1]: at_y = 1'b1;
    endcase
  end
  initial begin
    #1;
    at_sel = 2'b11;
    at_sel <= 2'b10;
    #1;
    `checkh(at_y, 1'b1);
  end

  // A process resumed from an event control in the same time step flushes its pending reports
  event ev_go;
  initial begin : event_resume
    logic [1:0] ev_sel;
    #1;
    ev_sel = 2'b11;
    unique case (1'b1)
      ev_sel[0]: ;
      ev_sel[1]: ;
    endcase
    @ev_go;
  end
  initial begin
    #1;
    ->>ev_go;
  end

  // Like a pending deferred assertion report (IEEE 1800-2023 16.4.4), a pending violation report
  // is flushed when the outermost scope of its process is disabled
  event dis_ready;
  initial begin : disable_victim
    logic [1:0] dis_sel;
    #1;
    dis_sel = 2'b00;
    priority case (1'b1)
      dis_sel[0]: ;
      dis_sel[1]: ;
    endcase
    ->dis_ready;
    #10;
  end
  initial begin
    @dis_ready;
    disable disable_victim;
  end

  initial begin
    #5;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
