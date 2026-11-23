// DESCRIPTION: Verilator: Invalid upward assertion control scopes
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

package bad_import_pkg;
  task automatic pk();
    check : assert (1'b1);
  endtask
endpackage

module bad_import_mid;
  initial $assertoff(0, pk);
endmodule

// From the mid in par, pk is par's generate block. From the mid in qar no pk is visible: the
// task imported into qar is not visible by hierarchical reference into qar (IEEE 1800-2023 26.3)
module bad_import_qar;
  import bad_import_pkg::*;
  bad_import_mid m ();
endmodule

module bad_import_par;
  if (1) begin : pk
    initial check : assert (1'b1);
  end
  bad_import_mid m ();
endmodule

// From the mid2 in qar2, pk is likewise not visible; from the mid2 in par2, no pk exists
module bad_import_mid2;
  initial $assertoff(0, pk);
endmodule

module bad_import_qar2;
  import bad_import_pkg::*;
  bad_import_mid2 m ();
endmodule

module bad_import_par2;
  bad_import_mid2 m ();
endmodule

module bad_import;
  bad_import_qar q ();
  bad_import_par p ();
  bad_import_par2 p2 ();
  bad_import_qar2 q2 ();
endmodule

module bad_out_mid;
  initial $assertoff(0, gb.c);
endmodule

module bad_out_leaf;
  initial check : assert (1'b1);
endmodule

// c is in par, not in gb, so gb.c names no scope (IEEE 1800-2023 23.6)
module bad_out_par;
  if (1) begin : gb
    if (1) begin : inner
      initial check : assert (1'b1);
    end
  end
  bad_out_leaf c ();
  bad_out_mid m ();
endmodule

module bad_out;
  bad_out_par p0 ();
  bad_out_par p1 ();
endmodule

package bad_pkg_pkg;
  task automatic gb();
    begin : inner
      check : assert (1'b1);
    end
  endtask
endpackage

module bad_pkg_mid;
  initial $assertoff(0, gb.inner);
endmodule

// In qar, gb names the package task imported there
module bad_pkg_qar;
  import bad_pkg_pkg::*;
  bad_pkg_mid m ();
endmodule

module bad_pkg_par;
  if (1) begin : gb
    if (1) begin : inner
      initial check : assert (1'b1);
    end
  end
  bad_pkg_mid m ();
endmodule

module bad_pkg;
  bad_pkg_qar q ();
  bad_pkg_par p ();
endmodule

module bad_missing_mid;
  initial $assertoff(0, gb.inner);
endmodule

module bad_missing_par;
  if (1) begin : gb
    if (1) begin : inner
      initial check : assert (1'b1);
    end
  end
  bad_missing_mid m ();
endmodule

// No gb is above this mid
module bad_missing_qar;
  bad_missing_mid m ();
endmodule

module bad_missing;
  bad_missing_qar q ();
  bad_missing_par p ();
endmodule

module t;
  bad_import import_case ();
  bad_out out_case ();
  bad_pkg pkg_case ();
  bad_missing missing_case ();
endmodule
