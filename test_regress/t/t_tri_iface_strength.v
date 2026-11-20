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

interface local_static_zero;
  wire value;
  assign (supply0, weak1) value = 1'b0;
  assign (strong0, strong1) value = 1'b1;
endinterface

interface local_static_one;
  wire value;
  assign (weak0, supply1) value = 1'b1;
  assign (strong0, strong1) value = 1'b0;
endinterface

interface wide_defaults;
  bit local_enable;
  bit [6:0] local_data;
  wire [101:7] value;
  assign (weak0, weak1) value = 95'h555555555555555555555555;
  assign (strong0, strong1) value[73:67] = local_enable ? local_data : 7'bz;
  modport drive(inout value);
endinterface

interface highz_zero;
  bit data;
  wire value;
  assign (weak0, weak1) value = 1'b0;
  assign (highz0, strong1) value = data;
endinterface

interface highz_one;
  bit data;
  wire value;
  assign (weak0, weak1) value = 1'b1;
  assign (strong0, highz1) value = data;
endinterface

`ifdef VERILATOR
interface equal_rank;
  wire value;
  assign (strong0, strong1) value = 1'b0;
endinterface
`endif

module wide_driver (
    wide_defaults.drive p,
    wide_defaults.drive alias_p,
    input bit enable,
    input bit [6:0] data
);
  assign (strong0, strong1) p.value[42:36] = enable ? data : 7'bz;
  assign (supply0, supply1) alias_p.value[91:85] = enable ? ~data : 7'bz;
endmodule

module wide_wrapper (
    wide_defaults.drive p,
    input bit enable,
    input bit [6:0] data
);
  // verilator inline_module
  wide_driver inner (
      p,
      p,
      enable,
      data
  );
endmodule

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

interface force_defaults;
  bit local_force = 1'b0;
  wire [6:0] value;
  assign (weak0, weak1) value = 7'h2a;
  always @(local_force)
    if (local_force) force value = 7'h4e;
    else release value;
endinterface

module force_driver (
    force_defaults p,
    input bit enable,
    input bit [6:0] data
);
  assign p.value = enable ? data : 7'bz;
endmodule

interface float_defaults;
  bit drive_on = 1'b0;
  bit [6:0] data = 7'h0;
  wire [6:0] value;
  assign (weak0, weak1) value = drive_on ? data : 7'bz;
  modport drive(inout value);
endinterface

interface zforce_defaults;
  bit drive_on = 1'b0;
  bit [3:0] bits = 4'b1100;
  wire [3:0] value;
  wire [3:0] src;
  assign (weak0, weak1) value = 4'b1111;
  assign (weak0, weak1) src = drive_on ? 4'b0110 : 4'bz;
endinterface

interface overlap_defaults;
  bit drive_on = 1'b0;
  // verilator lint_off ASCRANGE
  wire [1:4] value;
  // verilator lint_on ASCRANGE
  assign (weak0, weak1) value = drive_on ? 4'b0000 : 4'bz;
endinterface

module float_forcer (
    float_defaults.drive p,
    input bit force_on
);
  always @(force_on)
    if (force_on) force p.value[4:2] = 3'b011;
    else release p.value[4:2];
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
  local_static_zero local_zero ();
  local_static_one local_one ();
  wide_defaults wide ();
  wide_defaults wide_idle ();
  highz_zero hz_zero ();
  highz_one hz_one ();
`ifdef VERILATOR
  // Characterize the existing two-state OR approximation, not normative X resolution.
  equal_rank equal_opposite ();
  assign (strong0, strong1) equal_opposite.value = 1'b1;
`endif
  bit [6:0] wide_data = 0;
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
  wide_wrapper wide_drive (
      wide,
      enable,
      wide_data
  );
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

  // A force overrides every driver of the net; release restores the strength-resolved value
  // (IEEE 1800-2023 10.6.2).
  force_defaults forced ();
  force_defaults unforced ();
  bit force_enable = 1'b1;
  bit [6:0] force_data = 7'h15;
  force_driver forced_drive (
      forced,
      force_enable,
      force_data
  );
  force_driver unforced_drive (
      unforced,
      force_enable,
      force_data
  );
  initial begin
    #1;
    `checkh(forced.value, 7'h15);
    `checkh(unforced.value, 7'h15);
    force forced.value = 7'h63;
    #1;
    `checkh(forced.value, 7'h63);
    force_data = 7'h0c;
    #1;
    `checkh(forced.value, 7'h63);
    `checkh(unforced.value, 7'h0c);
    force_enable = 1'b0;
    release forced.value;
    #1;
    `checkh(forced.value, 7'h2a);
    `checkh(unforced.value, 7'h2a);
    force forced.value[4:2] = 3'b101;
    #1;
    `checkh(forced.value, 7'h36);
    force_enable = 1'b1;
    #1;
    `checkh(forced.value, 7'h14);
    release forced.value[4:2];
    #1;
    `checkh(forced.value, 7'h0c);
    forced.local_force = 1'b1;
    #1;
    `checkh(forced.value, 7'h4e);
    `checkh(unforced.value, 7'h0c);
    forced.local_force = 1'b0;
    #1;
    `checkh(forced.value, 7'h0c);
  end

  // Forced bits of a floating net are driven until release.
  float_defaults floating ();
  bit float_force = 1'b0;
  float_forcer float_force_drive (
      floating,
      float_force
  );
  initial begin
    #1;
    `checkh(floating.value, 7'bz);
    force floating.value = 7'h00;
    #1;
    `checkh(floating.value, 7'h00);
    `checkh(floating.value === 7'bz, 1'b0);
    release floating.value;
    #1;
    `checkh(floating.value, 7'bz);
    float_force = 1'b1;
    #1;
    `checkh(floating.value, 7'bzz011zz);
    floating.data = 7'h55;
    floating.drive_on = 1'b1;
    #1;
    `checkh(floating.value, 7'h4d);
    float_force = 1'b0;
    #1;
    `checkh(floating.value, 7'h55);
    floating.drive_on = 1'b0;
    #1;
    `checkh(floating.value, 7'bz);
  end
  float_defaults floating_cat ();
  bit float_other = 1'b0;
  initial begin
    #1;
    force {floating_cat.value[6:5], float_other} = 3'b101;
    #1;
    `checkh(floating_cat.value, 7'b10zzzzz);
    `checkh(float_other, 1'b1);
    release {floating_cat.value[6:5], float_other};
    #1;
    `checkh(floating_cat.value, 7'bz);
  end

  // A forced z bit is not driven, and a forced net follows the enable of its value.
  zforce_defaults zforced ();
  bit zforce_local_on = 1'b0;
  wire [3:0] zforce_local = zforce_local_on ? 4'b1001 : 4'bz;
  logic [3:0] zforce_data = 4'b0101;
  initial begin
    #1;
    force zforced.value = 4'b1z0z;
    #1;
    `checkh(zforced.value, 4'b1z0z);
    force zforced.value = zforced.src;
    #1;
    `checkh(zforced.value, 4'bz);
    zforced.drive_on = 1'b1;
    #1;
    `checkh(zforced.value, 4'b0110);
    force zforced.value = zforce_local;
    #1;
    `checkh(zforced.value, 4'bz);
    zforce_local_on = 1'b1;
    #1;
    `checkh(zforced.value, 4'b1001);
    force zforced.value[1:0] = zforced.src[2:1];
    #1;
    `checkh(zforced.value, 4'b1011);
    force zforced.value = zforce_data;
    #1;
    `checkh(zforced.value, 4'b0101);
    force zforced.value = zforced.bits;
    #1;
    `checkh(zforced.value, 4'b1100);
    zforced.bits = 4'b0011;
    #1;
    `checkh(zforced.value, 4'b0011);
    release zforced.value;
    #1;
    `checkh(zforced.value, 4'b1111);
  end

  // Overlapping forces and a partial release keep value and enable consistent.
  overlap_defaults overlapped ();
  initial begin
    #1;
    force overlapped.value[1:3] = 3'b101;
    #1;
    `checkh(overlapped.value, 4'b101z);
    force overlapped.value[2:4] = 3'b011;
    #1;
    `checkh(overlapped.value, 4'b1011);
    release overlapped.value[2:3];
    #1;
    `checkh(overlapped.value, 4'b1zz1);
    overlapped.drive_on = 1'b1;
    #1;
    `checkh(overlapped.value, 4'b1001);
    release overlapped.value;
    #1;
    `checkh(overlapped.value, 4'b0000);
  end

  initial begin
    bit [9:3] expected_down;
    bit [101:7] expected_wide;
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
      hz_zero.data = changing;
      hz_one.data = changing;
      wide_data = 7'(i * 13 + 5);
      wide.local_enable = supply_enable;
      wide.local_data = ~wide_data;
      expected_wide = 95'h555555555555555555555555;
      if (supply_enable) expected_wide[73:67] = ~wide_data;
      if (enable) begin
        expected_wide[42:36] = wide_data;
        expected_wide[91:85] = ~wide_data;
      end
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
      `checkh(local_zero.value, 1'b0);
      `checkh(local_one.value, 1'b1);
      `checkh(hz_zero.value, changing);
      `checkh(hz_one.value, changing);
      `checkh(wide.value, expected_wide);
      `checkh(wide_idle.value, 95'h555555555555555555555555);
`ifdef VERILATOR
      `checkh(equal_opposite.value, 1'b1);
`endif
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
