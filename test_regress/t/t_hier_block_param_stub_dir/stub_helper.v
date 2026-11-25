// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Found by library search from inside a hierarchical block, binding to a module outside it
module stub_helper;
  bind watched_lib drive u_lib_drive (.y(y));
endmodule
