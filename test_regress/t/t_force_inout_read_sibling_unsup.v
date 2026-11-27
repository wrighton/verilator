// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Forces of inout ports fed from an inout port, unsupported as without force domains

// Through a connection beside inout connections whose port nothing drives, and so do not drive it
module sub (
    inout wire x
);
endmodule
module leaf (
    inout wire p
);
endmodule
module mid (
    inout wire io
);
  wire a = io;
  sub s1 (a);
  sub s[1:0] (a);
  leaf l (a);
endmodule

// Through a connection beside other instances of its module, a force through a hierarchical
// reference perhaps forcing only one of them
module twin (
    inout wire x
);
endmodule
module twin_mid (
    inout wire io
);
  wire a = io;
  twin t1 (a);
  twin t2 (a);
endmodule

// Unlike a connection beside an instance of another module forced through a hierarchical
// reference, which drives it, so its force is supported, see t_force_inout_read_stop
module other (
    inout wire x
);
endmodule
module other_leaf (
    inout wire x
);
endmodule
module other_mid (
    inout wire io
);
  logic q;
  assign q = io;
  wire a = q;
  other o (a);
  other_leaf l (a);
endmodule

// Through its own connection, though the port drives it too
module self_leaf (
    inout wire p
);
  assign p = 1'b1;
endmodule
module self_mid (
    inout wire io
);
  wire a = io;
  self_leaf l (a);
endmodule

// Through a bit beside one that another inout connection drives
module bit_drive (
    inout wire p
);
  assign p = 1'b1;
endmodule
module bit_leaf (
    inout wire p
);
endmodule
module bit_mid (
    inout wire io
);
  wire [1:0] a;
  assign a = {2{io}};
  bit_drive d (a[1]);
  bit_leaf l (a[0]);
endmodule

// Through a streaming concatenation
module stream_leaf (
    inout wire [2:0] p
);
endmodule
module stream_mid (
    inout wire [2:0] io
);
  wire [2:0] b = {<<{io}};
  stream_leaf l (b);
endmodule

module t;
  wire n = 1'b1;
  wire [2:0] n3 = 3'b011;
  mid m (n);
  self_mid sm (n);
  bit_mid bm (n);
  stream_mid tm (n3);
  twin_mid wm (n);
  other_mid om (n);
  initial begin
    force m.l.p = 1'b0;
    force sm.l.p = 1'b0;
    force bm.l.p = 1'b0;
    force tm.l.p = 'z;
    force wm.t1.x = 1'b0;
    force om.o.x = 1'b1;
    force om.l.x = 1'b0;
  end
endmodule
