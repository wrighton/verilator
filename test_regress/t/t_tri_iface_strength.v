// DESCRIPTION: Verilator: Interface net drive-strength resolution
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got='h%x exp='h%x\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

interface default_zero;
  wire value;
  assign (weak0, weak1) value = 1'b0;
endinterface

interface default_one;
  wire value;
  assign (weak0, weak1) value = 1'b1;
endinterface

interface packed_defaults;
  wire [9:3] down;
  // verilator lint_off ASCRANGE
  wire [2:16] up;
  // verilator lint_on ASCRANGE
  assign (weak0, weak1) down = 7'h55;
  assign (weak0, weak1) up = 15'h5555;
  modport drive(inout down, up);
endinterface

interface constant_asym_zero;
  wire value;
  assign (weak0, strong1) value = 1'b0;
endinterface

interface constant_asym_one;
  wire value;
  assign (strong0, weak1) value = 1'b1;
endinterface

interface sole_asym;
  bit data;
  wire value;
  assign (weak0, strong1) value = data;
endinterface

interface rank_defaults;
  bit local_enable;
  bit local_data;
  wire value;
  assign (weak0, weak1) value = 1'b1;
  assign (strong0, strong1) value = local_enable ? local_data : 1'bz;
  modport drive(inout value);
endinterface

module rank_driver (
    rank_defaults.drive p,
    input bit supply_enable,
    input bit supply_data
);
  assign (pull0, pull1) p.value = 1'b0;
  assign (supply0, supply1) p.value = supply_enable ? supply_data : 1'bz;
endmodule

module packed_driver (
    packed_defaults.drive p,
    input bit enable,
    input bit [2:0] data
);
  assign (strong0, strong1) p.down[7:5] = enable ? data : 3'bzzz;
  assign p.up[5:7] = enable ? data : 3'bzzz;
endmodule

module flat_controls (
    output wire high_value,
    low_value
);
  assign (weak0, weak1) high_value = 1'b0;
  assign high_value = 1'b1;
  assign (weak0, weak1) low_value = 1'b1;
  assign low_value = 1'b0;
endmodule

module t;
  default_zero high_override ();
  default_zero idle_zero ();
  default_one low_override ();
  default_one idle_one ();
  default_zero dynamic_zero ();
  default_one dynamic_one ();
  default_zero released_zero ();
  default_one released_one ();
  packed_defaults packed_connected ();
  packed_defaults packed_idle ();
  rank_defaults ranked ();
  rank_defaults ranked_idle ();
  constant_asym_zero asym_zero ();
  constant_asym_one asym_one ();
  sole_asym asym_solo ();
  assign (pull0, pull1) asym_zero.value = 1'b1;
  assign (pull0, pull1) asym_one.value = 1'b0;
  bit supply_enable = 0;
  bit supply_data = 0;
  rank_driver rank_drive (
      ranked,
      supply_enable,
      supply_data
  );
  bit changing = 0;
  bit enable = 0;
  bit [2:0] data = 0;
  wire flat_high;
  wire flat_low;
  assign high_override.value = 1'b1;
  assign low_override.value = 1'b0;
  assign dynamic_zero.value = changing;
  assign dynamic_one.value = changing;
  assign released_zero.value = enable ? changing : 1'bz;
  assign released_one.value = enable ? changing : 1'bz;
  flat_controls flat (
      flat_high,
      flat_low
  );
  packed_driver driver (
      packed_connected,
      enable,
      data
  );

  initial begin
    bit [9:3] expected_down;
    // verilator lint_off ASCRANGE
    bit [2:16] expected_up;
    // verilator lint_on ASCRANGE
    for (int i = 0; i < 16; ++i) begin
      changing = i[0];
      enable = i[1];
      data = 3'(i);
      supply_enable = i[2];
      supply_data = i[3];
      ranked.local_enable = enable;
      ranked.local_data = changing;
      ranked_idle.local_enable = enable;
      ranked_idle.local_data = changing;
      asym_solo.data = changing;
      expected_down = 7'h55;
      expected_up = 15'h5555;
      if (enable) begin
        expected_down[7:5] = data;
        expected_up[5:7] = data;
      end
      #1;
      `checkh(flat_high, 1'b1);
      `checkh(flat_low, 1'b0);
      `checkh(high_override.value, 1'b1);
      `checkh(low_override.value, 1'b0);
      `checkh(idle_zero.value, 1'b0);
      `checkh(idle_one.value, 1'b1);
      `checkh(dynamic_zero.value, changing);
      `checkh(dynamic_one.value, changing);
      `checkh(released_zero.value, enable ? changing : 1'b0);
      `checkh(released_one.value, enable ? changing : 1'b1);
      `checkh(packed_connected.down, expected_down);
      `checkh(packed_connected.up, expected_up);
      `checkh(packed_idle.down, 7'h55);
      `checkh(packed_idle.up, 15'h5555);
      `checkh(ranked.value, supply_enable ? supply_data : (enable ? changing : 1'b0));
      `checkh(ranked_idle.value, enable ? changing : 1'b1);
      `checkh(asym_zero.value, 1'b1);
      `checkh(asym_one.value, 1'b0);
      `checkh(asym_solo.value, changing);
      #1;
      `checkh(high_override.value, 1'b1);
      `checkh(low_override.value, 1'b0);
      `checkh(packed_connected.down, expected_down);
      `checkh(packed_connected.up, expected_up);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
