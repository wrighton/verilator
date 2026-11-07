// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

`ifdef PERMISSION_BAD
class permission_payload;
  int value;
endclass
interface permission_vif;
  logic value;
endinterface
interface permission_if;
  permission_payload h;
  logic scalar;
  logic [1:0] words[2];
  virtual permission_vif vif;
  modport ro(input h, scalar, words, vif);
endinterface
module bad_view(permission_if.ro bus);
  permission_vif replacement ();
  initial begin
    bus.h = new;
    bus.scalar = 1'b1;
    bus.words[0] = 2'b10;
    bus.vif = replacement;
  end
endmodule
module t;
  permission_if bus ();
  bad_view u (bus);
endmodule

`elsif ASSIGNIN_CHECK
// ASSIGNIN remains on both an eligible net connection and a dropped variable connection.
module eligible_drv(input wire [1:0] a);
  assign a = 2'b11;
endmodule
module dropped_drv(input wire [1:0] a);
  assign a = 2'b11;
endmodule
module t;
  wire n0, n1;
  logic [1:0] v;
  eligible_drv u_net (.a({n1, n0}));
  dropped_drv u_var (.a(v));
endmodule

`endif
