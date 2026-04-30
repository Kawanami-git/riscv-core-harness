/*!
********************************************************************************
\file       target_pkg.sv
\brief      Targets for riscv-core-harness
\author     Kawanami
\date       28/04/2026
\version    1.0

\details
  riscv-core-harness supported targets.

\remarks

\section target_pkg_version_history Version history
| Version | Date       | Author   | Description                                 |
|:-------:|:----------:|:---------|:--------------------------------------------|
| 1.0     | 28/04/2026 | Kawanami | Initial version.                            |
********************************************************************************
*/


package target_pkg;
  /// RTL target (simulation)
  localparam int unsigned TARGET_RTL = 0;
  /// Microchip discovery kit target
  localparam int unsigned TARGET_MPFS_DISCOVERY_KIT = 1;
  /// Digilent cora z7-07s target
  localparam int unsigned TARGET_CORA_Z7_07S = 2;
endpackage


