// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Case equality with z of variables that are never z, next to a tristate net

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

package pkg;
  logic pv;
endpackage

module cell_var_driver (
    input logic [6:0] value,
    input logic enable,
    output wire [6:0] always_driven,
    output wire [6:0] may_float
);
  assign always_driven = value;
  assign may_float = enable ? 7'd0 : 7'bzzzzzzz;
endmodule

module sub (
    input logic [6:0] value,
    input logic enable,
    output bit local_is_z,
    output bit net_is_z,
    output bit up_plain_is_z,
    output bit up_tracked_is_z,
    output bit up_cell_driven_is_z,
    output bit up_cell_tracked_is_z
);
  logic [6:0] driven;
  always_comb driven = value;
  assign local_is_z = driven === 7'bzzzzzzz;

  // Only the parent observes the state of this variable.
  logic [6:0] down_tracked;
  always_comb down_tracked = enable ? 7'd0 : 7'bzzzzzzz;

  logic [6:0] cell_driven;
  logic [6:0] cell_tracked;
  cell_var_driver d (
      .value(value),
      .enable(enable),
      .always_driven(cell_driven),
      .may_float(cell_tracked)
  );

  wire [6:0] tri_net = enable ? 7'd0 : 7'bzzzzzzz;
  assign net_is_z = tri_net === 7'bzzzzzzz;
  assign up_plain_is_z = t.up_plain === 7'bzzzzzzz;
  assign up_tracked_is_z = t.up_tracked === 7'bzzzzzzz;
  assign up_cell_driven_is_z = t.up_cell_driven === 7'bzzzzzzz;
  assign up_cell_tracked_is_z = t.up_cell_tracked === 7'bzzzzzzz;
endmodule

module t (
    input clk
);

  integer cyc = 0;
  reg [63:0] crc = 64'h5aef0c8d_d70a4497;

  logic [3:0] a;
  logic b;
  wire local_is_z;
  wire net_is_z;
  wire up_plain_is_z;
  wire up_tracked_is_z;
  wire up_cell_driven_is_z;
  wire up_cell_tracked_is_z;
  logic [6:0] up_cell_driven;
  logic [6:0] up_cell_tracked;
  cell_var_driver up_driver (
      .value({5'b0, cyc[1:0]}),
      .enable(cyc[0]),
      .always_driven(up_cell_driven),
      .may_float(up_cell_tracked)
  );
  logic [6:0] up_plain;
  logic [6:0] up_tracked;
  always_comb up_plain = {5'b0, cyc[1:0]};
  always_comb up_tracked = cyc[0] ? 7'd0 : 7'bzzzzzzz;
  sub u (
      .value({5'b0, cyc[1:0]}),
      .enable(cyc[0]),
      .local_is_z(local_is_z),
      .net_is_z(net_is_z),
      .up_plain_is_z(up_plain_is_z),
      .up_tracked_is_z(up_tracked_is_z),
      .up_cell_driven_is_z(up_cell_driven_is_z),
      .up_cell_tracked_is_z(up_cell_tracked_is_z)
  );
  wire [1:0] w = crc[9:8];
  wire tri_net;
  wire [1:0] w_half;
  assign w_half[0] = crc[12];
  wire [3:0] w_part;
  assign w_part[1:0] = crc[14:13];
  assign tri_net = crc[10] ? crc[11] : 1'bz;

  // verilator lint_off UNDRIVEN
  wire undriven;
  logic unset;
  // verilator lint_on UNDRIVEN

  always_comb begin
    a = crc[3:0];
    b = crc[4];
    pkg::pv = crc[5];
  end

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    `checkd(a[1] === 1'bz, 1'b0);
    `checkd(a[1] !== 1'bz, 1'b1);
    `checkd(a === 4'bzzzz, 1'b0);
    `checkd(b === 1'bz, 1'b0);
    // Case equality distinguishes driven zero from high impedance (IEEE 1800-2023 11.4.5).
    `checkd(u.driven, {5'b0, cyc[1:0]});
    `checkd(local_is_z, 1'b0);
    `checkd(u.driven === 7'bzzzzzzz, local_is_z);
    `checkd(u.driven[0] !== 1'bz, 1'b1);
    `checkd(u.down_tracked === 7'bzzzzzzz, !cyc[0]);
    `checkd(u.down_tracked[0] !== 1'bz, cyc[0]);
    `checkd(u.cell_driven === 7'bzzzzzzz, 1'b0);
    `checkd(u.cell_tracked === 7'bzzzzzzz, !cyc[0]);
    `checkd(net_is_z, !cyc[0]);
    `checkd(up_plain_is_z, 1'b0);
    `checkd(up_tracked === 7'bzzzzzzz, !cyc[0]);
    `checkd(up_tracked_is_z, !cyc[0]);
    `checkd(up_cell_driven_is_z, 1'b0);
    `checkd(up_cell_tracked_is_z, !cyc[0]);
    `checkd(w === 2'bz0, 1'b0);
    `checkd(w[0] === 1'bz, 1'b0);
    `checkd(pkg::pv === 1'bz, 1'b0);
    `checkd(tri_net === 1'bz, !crc[10]);
    `checkd(undriven === 1'bz, 1'b1);
    `checkd(w_half[1] === 1'bz, 1'b1);
    `checkd(w_half[0] === 1'bz, 1'b0);
    `checkd(w_part[0] === 1'bz, 1'b0);
    `checkd(w_part[1] === 1'bz, 1'b0);
    `checkd(w_part[3:2] === 2'bzz, 1'b1);
    `checkd(unset === 1'bz, 1'b0);
    if (cyc == 20) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

endmodule
