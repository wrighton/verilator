// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2012 Jeremy Bennett
// SPDX-License-Identifier: CC0-1.0

// See issue #591

package pkg1;
  parameter PARAM2 = 16;
  parameter PARAM3 = 16;
endpackage : pkg1


package pkg10;
  import pkg1::*;
  import pkg1::*;  // Ignore if already
`ifdef T_PACKAGE_EXPORT
  export * ::*;  // Not supported on all simulators
`endif
  parameter PARAM1 = 8;
endpackage
package pkg11;
  import pkg10::*;
endpackage

package pkg20;
  import pkg1::*;
`ifdef T_PACKAGE_EXPORT
  export pkg1::*;
`endif
  parameter PARAM1 = 8;
endpackage
package pkg21;
  import pkg20::*;
endpackage

package pkg30;
  import pkg1::*;
`ifdef T_PACKAGE_EXPORT
  export pkg1::PARAM2; export pkg1::PARAM3;
`endif
`ifdef T_PACKAGE_EXPORT_BAD
  export pkg1::BAD_DOES_NOT_EXIST;
`endif
  parameter PARAM1 = 8;
endpackage
package pkg31;
  import pkg30::*;
endpackage

// IEEE 1800-2023 26.6: A package export may precede a corresponding package import
package pkg40;
  export pkg1::PARAM2;
  export pkg1::*;
  import pkg1::PARAM2;
  import pkg1::PARAM3;
  parameter PARAM1 = 8;
endpackage
package pkg41;
  import pkg40::*;
endpackage

package pkg50;
  export *::*;
  import pkg1::*;
  parameter PARAM1 = PARAM2 + PARAM3 - 24;
endpackage
package pkg51;
  import pkg50::*;
endpackage

module t;

  reg [pkg11::PARAM1 : 0] bus11;
  reg [pkg11::PARAM2 : 0] bus12;
  reg [pkg11::PARAM3 : 0] bus13;

  reg [pkg21::PARAM1 : 0] bus21;
  reg [pkg21::PARAM2 : 0] bus22;
  reg [pkg21::PARAM3 : 0] bus23;

  reg [pkg31::PARAM1 : 0] bus31;
  reg [pkg31::PARAM2 : 0] bus32;
  reg [pkg31::PARAM3 : 0] bus33;

  reg [pkg41::PARAM1 : 0] bus41;
  reg [pkg41::PARAM2 : 0] bus42;
  reg [pkg41::PARAM3 : 0] bus43;

  reg [pkg51::PARAM1 : 0] bus51;
  reg [pkg51::PARAM2 : 0] bus52;
  reg [pkg51::PARAM3 : 0] bus53;

  initial begin
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
