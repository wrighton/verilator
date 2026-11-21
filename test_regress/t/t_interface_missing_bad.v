// DESCRIPTION: Verilator: Missing interface test
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2015 Todd Strader
// SPDX-License-Identifier: CC0-1.0

// Interface intentionally not defined
//interface foo_intf;
//   logic a;
//endinterface

module foo_mod (
    foo_intf foo
);
endmodule

module foo_mp_mod (
    foo_intf.mp foo
);
endmodule

module t;

  foo_intf the_foo ();

  foo_mod foo_mod (.foo(the_foo));
  foo_mp_mod foo_mp_mod (.foo(the_foo));

  initial begin
    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
