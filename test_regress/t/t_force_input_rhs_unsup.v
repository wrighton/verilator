// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module rhs_helper (
    input wire [6:0] pulled_rhs,
    input wire [6:0] forced_rhs,
    input wire [6:0] primary_rhs,
    input wire ren
);
  wire [6:0] n_pull, n_force, n_primary;
  assign n_pull = ren ? 7'h33 : 7'bz;
  assign n_force = ren ? 7'h2a : 7'bz;
  assign n_primary = ren ? 7'h5a : 7'bz;
  initial begin
    #1;
    force n_pull = pulled_rhs;
    force n_force = forced_rhs;
    force n_primary = primary_rhs;
  end
endmodule

module rhs_relay (
    input wire [6:0] pulled_rhs,
    input wire [6:0] forced_rhs,
    input wire [6:0] primary_rhs,
    input wire ren
);
  initial #1 force forced_rhs = 7'h15;
  rhs_helper h (.*);
endmodule

module t (
    input wire [6:0] primary_rhs,
    input wire ren
);
  tri1 [6:0] a;
  assign a = ren ? 7'h15 : 7'bz;
  rhs_relay relay (
      .pulled_rhs(a),
      .forced_rhs(7'h00),
      .*
  );
endmodule
