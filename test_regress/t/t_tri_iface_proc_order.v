// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Michael Wrighton
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

interface proc_value;
  logic [32:0] value;
endinterface

// Declared before the writers, so processed after them, yet its z makes the interface variable
// tristate for every instance
module z_writer (
    proc_value p
);
  initial p.value = 'z;
endmodule

// Writes of one process without z, through a port, read back as written
module flat_writer (
    proc_value p
);
  initial begin
    p.value = 33'h1_0000_0003;
    #1;
    `checkh(p.value, 33'h1_0000_0003);
    p.value = 33'h0_0000_0005;
    #1;
    `checkh(p.value, 33'h0_0000_0005);
  end
endmodule

module block_writer (
    proc_value p
);
  initial begin
    begin : b
      p.value = 33'h1_0000_0006;
      #1;
      `checkh(p.value, 33'h1_0000_0006);
    end
    p.value = 33'h0_0000_0009;
    #1;
    `checkh(p.value, 33'h0_0000_0009);
  end
endmodule

// A z that is tested or counted, not written, does not make the variable tristate, so a plain
// write of another module is not resolved with it
interface test_value;
  logic [7:0] value;
endinterface

module z_tester (
    test_value p
);
  logic [3:0] sel = 4'b1001;
  initial begin
    p.value = (sel === 4'bz) ? 8'h11 : 8'h12;
    #1;
    p.value = (sel ==? 4'b1zz1) ? 8'h13 : 8'h14;
    #1;
    p.value = (sel inside {4'b1??1}) ? 8'h15 : 8'h16;
    #1;
    p.value = $countbits(sel, 1'bz) == 0 ? 8'h17 : 8'h18;
  end
endmodule

module plain_writer (
    test_value p
);
  initial begin
    #4;
    p.value = 8'h22;
    #1;
    `checkh(p.value, 8'h22);
  end
endmodule

module t;
  proc_value zv ();
  z_writer z_drive (zv);
  proc_value fv ();
  flat_writer flat_drive (fv);
  proc_value bv ();
  block_writer block_drive (bv);
  test_value tz ();
  z_tester tester (tz);
  test_value tp ();
  plain_writer plain_drive (tp);
  z_tester tester2 (tp);
  initial begin
    #3;
    `checkh(zv.value === 33'bz, 1'b1);
    #3;
    `checkh(tz.value, 8'h17);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
