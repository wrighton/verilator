// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  bit clk = 0;

  // Forces or releases a variable through the VPI
  import "DPI-C" function void dpii_force(input string name, input int value, input bit do_release);

  // Registered feedback through blocks, with a plain and with a forceable input
  wire q_plain, q_force;
  fb_plain u_plain (
      .clk(clk),
      .d(~q_plain),
      .q(q_plain)
  );
  fb_force u_force (
      .clk(clk),
      .d(~q_force),
      .q(q_force)
  );

  // Registered feedback through a block whose register has a declaration initializer
  wire q_init;
  fb_init u_init (
      .clk(clk),
      .d(~q_init),
      .q(q_init)
  );

  // Registered feedback through a block with a latch clock gate
  wire q_gate;
  fb_gate u_gate (
      .clk(clk),
      .en(1'b1),
      .d(~q_gate),
      .q(q_gate)
  );

  // Registered feedback through a block whose output is assigned from its register
  wire q_alias;
  fb_alias u_alias (
      .clk(clk),
      .d(~q_alias),
      .q(q_alias)
  );

  // A combinational output beside a registered output fed back
  wire [6:0] o_comb, q_reg;
  comb_reg u_comb (
      .clk(clk),
      .i(q_reg + 7'd3),
      .o(o_comb),
      .q(q_reg)
  );

  // Registered feedback through a block with ports named like the functions of its wrapper
  wire q_names;
  fb_names u_names (
      .clk(clk),
      .d(~q_names),
      .fb_names_protectlib_check_hash(1'b1),
      .fb_names_protectlib_create(1'b1),
      .fb_names_protectlib_combo_update(1'b1),
      .fb_names_protectlib_seq_update(1'b1),
      .fb_names_protectlib_combo_ignore(),
      .fb_names_protectlib_final(),
      .fb_names_protectlib_settle(),
      .fb_names_protectlib_vpi_written(),
      .q(q_names)
  );

  initial begin
    for (int k = 1; k <= 4; ++k) begin
      #1 clk = 1;
      #1;
      `checkh(q_plain, k[0]);
      `checkh(q_force, k[0]);
      `checkh(q_alias, k[0]);
      `checkh(q_init, k[0]);
      `checkh(q_gate, k[0]);
      `checkh(q_names, k[0]);
      `checkh(q_reg, 7'(3 * k));
      `checkh(o_comb, 7'(3 * k + 3));
      clk = 0;
    end
    // A forced registered output reaches the parent, and the combinational path from it
    dpii_force("t.u_comb.q", 'h55, 1'b0);
    #1;
    `checkh(q_reg, 7'h55);
    `checkh(o_comb, 7'h58);
    dpii_force("t.u_comb.q", 0, 1'b1);
    #1 clk = 1;
    #1;
    `checkh(q_reg, 7'h58);
    `checkh(o_comb, 7'h5b);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule

module fb_plain (
    input bit clk,
    input bit d,
    output bit q
);
  /*verilator hier_block*/
  always_ff @(posedge clk) q <= d;
endmodule

module fb_force (
    input bit clk,
    input bit d  /*verilator forceable*/,
    output bit q
);
  /*verilator hier_block*/
  always_ff @(posedge clk) q <= d;
endmodule

module fb_init (
    input logic clk,
    input logic d,
    output logic q = 1'b0
);
  /*verilator hier_block*/
  always_ff @(posedge clk) q <= d;
endmodule

module fb_gate (
    input bit clk,
    input bit en,
    input bit d,
    output bit q
);
  /*verilator hier_block*/
  bit en_l;
  always_latch if (!clk) en_l = en;
  wire gclk = clk & en_l;
  always_ff @(posedge gclk) q <= d;
endmodule

module fb_names (
    input bit clk,
    input bit d,
    input bit fb_names_protectlib_check_hash,
    input bit fb_names_protectlib_create,
    input bit fb_names_protectlib_combo_update,
    input bit fb_names_protectlib_seq_update,
    output bit fb_names_protectlib_combo_ignore,
    output bit fb_names_protectlib_final,
    output bit fb_names_protectlib_settle,
    output bit fb_names_protectlib_vpi_written,
    output bit q
);
  /*verilator hier_block*/
  always_ff @(posedge clk)
    q <= d & fb_names_protectlib_check_hash & fb_names_protectlib_create
        & fb_names_protectlib_combo_update & fb_names_protectlib_seq_update;
  assign fb_names_protectlib_combo_ignore = q;
  assign fb_names_protectlib_final = q;
  assign fb_names_protectlib_settle = q;
  assign fb_names_protectlib_vpi_written = q;
endmodule

module fb_alias (
    input bit clk,
    input bit d,
    output bit q
);
  /*verilator hier_block*/
  bit q_r;
  always_ff @(posedge clk) q_r <= d;
  assign q = q_r;
endmodule

module comb_reg (
    input logic clk,
    input logic [6:0] i,
    output logic [6:0] o,
    output bit [6:0] q  /*verilator public_flat_rw*/  /*verilator forceable*/
);
  /*verilator hier_block*/
  assign o = i;
  always_ff @(posedge clk) q <= i;
endmodule
