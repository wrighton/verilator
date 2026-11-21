// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

interface ifc #(
    parameter int PARAM = 1
);
  logic [PARAM-1:0] v;
  modport rd(input v);
endinterface

module leaf (
    interface d
);
  initial begin
    #1;
    `checkd(d.v, 13);
    `checkd(d.PARAM, 5);
  end
endmodule

module mid2 (
    interface c
);
  leaf leaf_i (.d(c));
endmodule

module mid1 (
    interface b
);
  mid2 mid2_i (.c(b));
endmodule

// Generic leaf reporting what its port is connected to
module leaf_val (
    interface d,
    output int width,
    output int value
);
  assign width = $bits(d.v);
  assign value = int'(d.v);
endmodule

module leaf_rd (
    interface.rd d,
    output int width,
    output int value
);
  assign width = $bits(d.v);
  assign value = int'(d.v);
endmodule

module leaf_array (
    interface d[2],
    output int value
);
  assign value = int'(d[0].v) * 100 + int'(d[1].v);
endmodule

// Named interface port connected to a generic interface port
module named (
    ifc c,
    output int width,
    output int value
);
  leaf_val leaf_i (
      .d(c),
      .width(width),
      .value(value)
  );
endmodule

// Named interface port with modport connected to a generic interface port with modport
module named_rd (
    ifc.rd c,
    output int width,
    output int value
);
  leaf_rd leaf_i (
      .d(c),
      .width(width),
      .value(value)
  );
endmodule

// Named interface port array, and an element of it, connected to generic interface ports
module named_array (
    ifc c[3:2],
    output int value,
    output int value_elem
);
  leaf_array leaf_i (
      .d(c),
      .value(value)
  );
  leaf_val leaf_elem_i (
      .d(c[2]),
      .width(),
      .value(value_elem)
  );
endmodule

// Generic interface port array, and an element of it, connected to generic interface ports
module generic_array (
    interface c[1:2],
    output int value,
    output int value_elem
);
  leaf_array leaf_i (
      .d(c),
      .value(value)
  );
  leaf_val leaf_elem_i (
      .d(c[1]),
      .width(),
      .value(value_elem)
  );
endmodule

module t;
  ifc #(.PARAM(5)) a ();
  mid1 mid1_i (.b(a));
  initial a.v = 13;

  ifc #(.PARAM(7)) n7 ();
  ifc #(.PARAM(15)) n15 ();
  int width_n7, value_n7, width_n15, value_n15, width_rd, value_rd;
  named named_n7 (
      .c(n7),
      .width(width_n7),
      .value(value_n7)
  );
  named named_n15 (
      .c(n15),
      .width(width_n15),
      .value(value_n15)
  );
  named_rd named_rd_n15 (
      .c(n15),
      .width(width_rd),
      .value(value_rd)
  );
  initial begin
    n7.v = 7'd101;
    n15.v = 15'd20001;
    #1;
    `checkd(width_n7, 7);
    `checkd(value_n7, 101);
    `checkd(width_n15, 15);
    `checkd(value_n15, 20001);
    `checkd(width_rd, 15);
    `checkd(value_rd, 20001);
  end

  ifc #(.PARAM(9)) arr[0:1] ();
  int value_arr, value_arr_elem;
  named_array named_arr (
      .c(arr),
      .value(value_arr),
      .value_elem(value_arr_elem)
  );
  initial begin
    arr[0].v = 9'd11;
    arr[1].v = 9'd22;
    #1;
    `checkd(value_arr, 1122);
    `checkd(value_arr_elem, 22);
  end

  ifc #(.PARAM(11)) garr[3:2] ();
  int value_garr, value_garr_elem;
  generic_array generic_arr (
      .c(garr),
      .value(value_garr),
      .value_elem(value_garr_elem)
  );
  initial begin
    garr[3].v = 11'd33;
    garr[2].v = 11'd44;
    #1;
    `checkd(value_garr, 3344);
    `checkd(value_garr_elem, 33);
  end

  initial begin
    #2;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
