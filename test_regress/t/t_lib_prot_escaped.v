// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%0x exp='h%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

`ifdef SECRET_SOURCE
// Built into a --protect-lib library; its port names are escaped identifiers
module secret (
    input clk,
    input [6:0] \d// ,
    output logic [6:0] \q.x ,
    output [6:0] \c[2] ,
    input \z.oe ,
    input \z.drive ,
    inout wire \z// ,
    output \z.read
);
  always_ff @(posedge clk) \q.x <= \d// + 7'd1;
  assign \c[2] = ~\d// ;
  assign \z// = \z.oe ? \z.drive : 1'bz;
  assign \z.read = \z// ;
endmodule
`else
module t (
    input clk
);
  int cyc = 0;
  logic [6:0] d;
  logic [6:0] q;
  logic [6:0] c;

  assign d = 7'(cyc * 5);

  wire z_oe = cyc[0];
  wire z_drive = cyc[1];
  wire z_external = cyc[2];
  wire z_expected = z_oe ? z_drive : z_external;
  // The DPI update reads this net and writes its driver in the same call.
  /* verilator lint_off UNOPTFLAT */
  wire z_bus;
  /* verilator lint_on UNOPTFLAT */
  wire z_read;
  assign z_bus = z_oe ? 1'bz : z_external;

  always @(negedge clk) begin
    `checkh(z_bus, z_expected);
    `checkh(z_read, z_expected);
  end

  // Uses the library through its generated wrapper
  secret u_secret (
      .clk(clk),
      .\d// (d),
      .\q.x (q),
      .\c[2] (c),
      .\z.oe (z_oe),
      .\z.drive (z_drive),
      .\z// (z_bus),
      .\z.read (z_read)
  );

  always @(posedge clk) begin
    cyc <= cyc + 1;
    `checkh(c, ~d);
    if (cyc > 0) `checkh(q, 7'((cyc - 1) * 5 + 1));
    if (cyc == 30) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
`endif
