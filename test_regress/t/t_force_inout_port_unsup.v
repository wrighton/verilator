// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module force_boundary (
    inout wire [6:0] p
);
  initial begin
    force p = 7'h00;
    #1;
    release p;
  end
endmodule

module pass_through (
    inout wire [6:0] p
);
  force_boundary child (.p(p));
endmodule

// Ports other than a packed wire or tri net
module wand_port (
    inout wand [6:0] p
);
  initial force p = 7'h00;
endmodule

module strength_port (
    inout wire [6:0] p
);
  assign (weak0, weak1) p = 7'h01;
  initial force p = 7'h00;
endmodule

module force_external (
    inout wire [6:0] p
);
endmodule

module unconnected_driven (
    inout wire [6:0] p
);
  assign p = 7'h35;
  initial force p = 7'h00;
endmodule

module t;
  logic [6:0] raw = 7'h11;
  // Connections other than as one plain net
  wire [13:0] wide;
  assign wide = {raw, raw};
  force_boundary select_h (.p(wide[6:0]));
  wire signed [6:0] signed_net;
  assign signed_net = raw;
  force_boundary signed_h (.p(signed_net));
  wire [6:0] folded;
  assign folded = 7'h11;
  force_boundary folded_h (.p(folded[6:0]));
  wire [6:0] chained;
  assign chained = raw;
  pass_through mid_h (.p(chained));
  wire [6:0] #1 delayed;
  assign delayed = raw;
  force_boundary delay_h (.p(delayed));
  tri1 [6:0] pulled;
  assign pulled = raw;
  force_boundary pull_h (.p(pulled));
  wire [6:0] weak_drv;
  assign (strong0, weak1) weak_drv = raw;
  force_boundary strength_h (.p(weak_drv));
  wire [6:0] pub  /*verilator public_flat_rw*/;
  assign pub = raw;
  force_boundary public_h (.p(pub));
  wire [6:0] frc  /*verilator forceable*/;
  assign frc = raw;
  force_boundary forceable_h (.p(frc));
  wire [6:0] wand_net;
  wand_port wand_h (.p(wand_net));
  wire [6:0] strength_net;
  strength_port strength_port_h (.p(strength_net));
  // A port also forced from another module
  force_boundary xref_h (.p(wide[13:7]));
  initial force xref_h.p = 7'h00;
  // A hierarchical force still requires a supported bidirectional connection.
  force_external selected_external (.p(wide[6:0]));
  force_external concat_external (.p({wide[13:11], wide[3:0]}));
  initial begin
    force selected_external.p = 7'h7f;
    force concat_external.p = 7'h7f;
  end
  unconnected_driven undriven_boundary (.p());
endmodule
