# Contributing.md

This document consolidates the coding standards for **SystemVerilog/Verilog (HDL)** and **C/C++** used in this project.  
All contributors must follow these rules. Automated formatters/linters are recommended wherever possible.

---

## 0. License Headers

- Every source file must start with an SPDX header:
  - `// SPDX-License-Identifier: MIT` (for C/C++ headers/sources and HDL)
- `LICENSE.md` at the repository root defines the global license.

---

## 1. Repository Layout

- RTL under `hardware/`
- Simulation under `simulation/`
- Platform software under `software/platform/`
- Firmware under `software/firmware/`
- Any generated file under `work/`

Use **lowercase_with_underscores** for filenames. One logical unit per file (e.g., 1 module, 1 class, 1 component).

---

# Part A — HDL Style Guide (SystemVerilog/Verilog)

### A.1 File Organization
- One module/interface/package per file.
- File name matches the top-level module name (e.g., `decode.sv` → `module decode`).
- Keep synthesizable RTL separate from TB/bench utilities.

### A.2 Formatting
- Indentation: **2 spaces**, no tabs (Makefiles excluded).
- Max line length ~ **100 cols**.
- No trailing whitespace.
- Use the provided automatic formatting (Verible).
- Avoid blank lines in port/parameter lists (Doxygen); use short comment dividers instead.

**Example (ports):**
```systemverilog
module foo (
  /* Clock & Reset */
  /// System clock
  input  wire clk_i,
  /// Active-low reset
  input  wire rstn_i,
  /* Control */
  input  wire start_i,
  output wire busy_o
);
endmodule
```

### A.3 Naming

- **Modules / packages**: `snake_case`  
- **Signals**: `snake_case`  
  - Inputs: suffix `_i`  
  - Outputs: suffix `_o`  
  - Inouts: suffix `_io`  
  - Registered signals: `_q`  
  - Delayed signals: `_d`  
- **Clock / reset**:  
  - Clock: `clk_i`  
  - Reset: `rstn_i` (active low, synchronous release)  
- **Parameters**: `UpperCamelCase`  
- **Constants / localparams**: `ALL_CAPS`
- **Enum**: snake_case + suffix `_e`
- **typedef**: snake_case + suffix `_t`

## A.4. Types and Declarations

- Use `wire` for nets and `reg` for storage/procedural signals (preferred).  
  *(Note: `logic` is permitted by SystemVerilog but is discouraged in this project.)*
- **Discipline:**
  - Sequential (`always_ff`): `reg` with non-blocking assignments (`<=`).  
  - Combinational (`always_comb`): `reg`/`wire` destinations with blocking assignments (`=`).  
  - Latches (`always_latch`): `reg` with blocking assignments (`=`).  
- Use `typedef enum logic [...]` for FSM states (enum base type can be `logic` while signals remain `reg`).

### A.5 Always Blocks

**Sequential logic** (`always_ff`):
```systemverilog
reg [31:0] q, d;

always_ff @(posedge clk_i) begin
  if (!rstn_i) begin
    q <= '0;
  end else begin
    q <= d;
  end
end
```
- Use non-blocking assignments (`<=`).  
- All flops must be initialized in the reset branch.  
- Do not gate clocks; use enables inside the `always_ff`.

**Combinational logic** (`always_comb`):
```systemverilog
reg y;

always_comb begin
  // defaults
  y = '0;
  // logic
  y = a & b;
end
```
- Use blocking assignments (`=`).  
- Do not write manual sensitivity lists.  
- Provide **total assignment** to avoid unintended latches (initialize outputs at the top).

**Level-sensitive latches** (`always_latch`) — **discouraged, demo kept explicit**
```systemverilog
reg latch_q;

always_latch begin
  latch_q = latch_q;  // explicit hold (demonstration on intent)
  if (en_i) begin
    latch_q = d_i;
  end
end
```
**Rules for latches:**
- Must be confined to a **whitelisted module**; document the reason in a banner comment.  
- No cross-clock-domain usage.  
- Declare intent with `always_latch` (never `always @(*)` that infers a latch implicitly).  
- Provide a default/hold assignment at the top of the block.  

### A.6 Reset
- Default: synchronous active-low reset named `rstn_i`.  
- Asynchronous resets must be justified and named `arstn_i` (deassert synchronized).  
- All sequential elements must have a defined reset value; do not rely on simulator initials.

### A.7 Assertions (Optional)
- SystemVerilog Assertions (`assert`) may be used to check parameters/protocols.  
- Keep them synthesizable-safe or guard with synthesis directives.  
- Example:
```systemverilog
initial begin : param_checks
  if (!(ARCHI == 32 || ARCHI == 64)) begin
    $fatal(1, "Only 32-bit and 64-bit architectures are supported (ARCHI=%0d).", ARCHI);
  end
end
```

### A.8 Warnings
All warnings must be documented. A detailed explanation must be provided to describe why each warning has been ignored.

This documentation shall appear in the README.md file of each branch.

### A.9 Documentation
- English comments.
- Doxygen-compatible comments (`///` or `/*! ... */`) for parameters/ports.
- Each file starts with banner:
```systemverilog
// SPDX-License-Identifier: MIT
/*!
********************************************************************************
\file       filename
\brief      Description
\author     Your Name
\date       xx/xx/xxxx
\version    x.x

\details
  Provide details here

\remarks
- This implementation complies with [reference or standard].
- TODO: [possible improvements or future features]

\section modulename_version_history Version history
| Version | Date       | Author     | Description                               |
|:-------:|:----------:|:-----------|:------------------------------------------|
| 1.0     | xx/xx/xxxx | Your Name  | Description                               |
| 1.1     | xx/xx/xxxx | Your Name  | Description                               |
********************************************************************************
*/
```

---

# Part B — C/C++ Style Guide

### B.1 Language & Tooling
- **C++** for platform software. **C** for firmware.
- Headers use `.h`, C++ sources use `.cpp` and C sources use `.c`.
- Use `<c...>` headers (`<cstdint>`, `<cstdio>`, …) in C++.
- Build warnings as errors recommended. Enable `-Wall -Wextra -Wpedantic` (and platform equivalents).

### B.2 Formatting
- Indentation: **2 spaces**; no tabs.
- Max line length ~ **100 cols**.
- Brace style: K&R/Allman acceptable; be consistent (project uses K&R).
- One statement per line; no trailing whitespace.
- Use the provided clang-format. Do not hand-align.

### B.3 Naming
- **Types (classes/structs/enums):** `UpperCamelCase`
- **Functions (API):** `UpperCamelCase` (e.g., `SetupAxi4`, `ParseSpike`)
- **Local variables / parameters:** `lower_snake_case`
- **Constants/macros:** `ALL_CAPS`
- **Global/static functions:** `UpperCamelCase` (mirror API) or `internal_lower_snake_case` if clearly internal; prefer anonymous namespaces in `.cpp`.
- **Getters/Setters:** `GetFoo()`, `SetFoo(...)`.

### B.4 Headers
- Header guards: `#ifndef FILENAME_H` / `#define FILENAME_H` / `#endif` (simple form).
- Keep headers self-contained. Include only what you need.
- Place function docs (Doxygen `\brief`, params, return) in headers; `.cpp` uses shorter inline comments for internal mechanics.

### B.5 Const-correctness & References
- Use `const` and `&` where appropriate:
  - `const std::string&` for read-only inputs.
  - `const T*` / `T*` for raw buffers; prefer spans or iterators when available.

### B.6 Error Handling
- Return explicit status codes (`SUCCESS`, `FAILURE`, …) or `enum class` for richer APIs.
- For fatal conditions in simulation tools, `std::exit(EXIT_FAILURE)` is acceptable after logging.
- Prefer not to throw exceptions across C/Verilator boundaries.

### B.7 Thread-Safety / Concurrency
- Logging functions using global state must serialize (e.g., `flock`, mutex) if used cross-thread.
- Keep simulation single-threaded unless stated otherwise.

### B.8 Includes & Namespaces
- Order: corresponding header → C/C++ stdlib → third-party → project headers.
- Avoid `using namespace std;` in headers. In `.cpp`, limit scope.

### B.9 Comments & Documentation
- English only.
- High-level Doxygen in headers. Internal rationale and mechanics as `//` comments in `.cpp`.
- Keep docs adjacent to declarations (headers) and non-duplicative.

### B.10 Build Macros & Portability
- Minimize `#ifdef` scatter; centralize platform switches.
- Separate SIM (Verilator) vs platform code paths behind small, well-documented adaptor APIs.

### B.11 Return Codes
- Reuse project-wide codes from `defines.h`:
  - `SUCCESS (0x00)`, `FAILURE (0x01)`, `ADDR_NOT_ALIGNED`, `INVALID_ADDR`, `INVALID_SIZE`, `OVERFLOW`, …
- Functions must document `\return` values in headers.

### B.12 I/O & Logging
- Use the project logger API for normal logs.
- Console output (`printf`/`cout`) only for user prompts or fatal fallbacks.
- For waveforms/traces, keep file naming deterministic via args parser.

### B.13 Simulation Conventions
- Time base constants: see `sim.h` (`VERILATOR_TICK`, `CLOCK`, `SIM_STEP`).  
- Half-cycle = `Tick()`, full cycle = `Cycle()`; `Comb()` evaluates without time advance.
- Keep DUT interaction isolated in `simulation/` (no direct access from platform code).

---

# Part C — Workflow & Commits

### C.1 Formatting/Linting
- Run formatters/linters pre-commit (hook recommended). Commits failing checks are rejected.

### C.2 Conventional Commits
**Format**  
`type: subject`  
(blank line)  
`body (optional, wrap at 72 cols)`

**Types**:
- `feat`: a new user-visible feature or functional addition
- `fix`: a bug fix or correction of incorrect behavior
- `docs`: documentation-only changes
- `style`: formatting or style-only changes that do not affect behavior
- `refactor`: code changes that improve structure or readability without changing behavior
- `perf`: performance improvements
- `test`: adding or updating tests
- `build`: changes to build system, dependencies, or compilation flow
- `ci`: changes to continuous integration or automation pipelines
- `chore`: maintenance tasks or non-functional updates that do not fit other types
- `revert`: reverting a previous commit
- `work`: temporary work-in-progress snapshot used to save ongoing local development;
  these commits should normally be cleaned up, squashed, or rewritten before
  merging into the main branch

**Breaking changes**: use `!` after type.  
Example: `feat!: change ALU interface to add carry-in`

### C.3 Git Workflow
Each feature, fix, or refactoring should be developed on a dedicated working
branch.

During development, temporary commits such as `work:` commits are allowed to
save progress and avoid losing ongoing work. These intermediate commits are
intended for the working branch only.

Once the modification is complete and validated, the working branch should be
integrated into the main branch using a **squash merge**. This ensures that the
main branch keeps a clean and readable history, with a single final commit
written using a proper Conventional Commit type and message.

### C.4 Examples
```
feat(decode): add compressed instruction decoding (C extension)

- Add tables for C.ADDI/C.LI/C.J variants
- Extend immediate extractor to handle C formats
```

```
fix(axi): correct awsize encoding for RV64 single-beat writes
```

```
style(sim): apply clang-format and remove trailing whitespace
```

---

# Part D — Doxygen Tips

- **C/C++**: Place the detailed `\brief/\param/\return` blocks in the **header**.  
  `.cpp` files should only contain short internal comments.
- **HDL**: Use `///` on ports/parameters; banner at file top.  
- For generated docs, consider enabling `ENABLE_PREPROCESSING=NO` in HDL-only runs to avoid macro stripping; enable it when documenting C/C++ with macros.
- Prefer unified groups: `\defgroup`, `\addtogroup` for related modules.

---

## Appendix — Quick Checklists

**HDL PR checklist**
- [ ] SPDX and Doxygen headers
- [ ] Doxygen comments
- [ ] No unintended latches
- [ ] Reset paths initialized
- [ ] Lint/format pass

**C/C++ PR checklist**
- [ ] SPDX and Doxygen headers
- [ ] Doxygen comments
- [ ] Const-correctness
- [ ] Error codes documented
- [ ] No `using namespace std;` in headers
- [ ] Format/lint pass
