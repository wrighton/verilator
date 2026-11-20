// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

interface strength_defaults;
  bit drive_on = 1'b0;
  bit plain = 1'b1;
  wire value;
  wire src;
  assign (weak0, weak1) value = 1'b0;
  assign (weak0, weak1) src = drive_on ? 1'b1 : 1'bz;
endinterface

module t;
  strength_defaults bus ();
  bit local_on = 1'b0;
  wire local_src = local_on ? 1'b1 : 1'bz;
  task automatic force_value;
    force bus.value = 1'b1;
  endtask
  task automatic release_value;
    release bus.value;
  endtask
  initial begin
    force_value();
    release_value();
    force bus.value = ~bus.src;
    force bus.value = bus.plain;
    force bus.value = ~local_src;
    release bus.value;
  end
endmodule
