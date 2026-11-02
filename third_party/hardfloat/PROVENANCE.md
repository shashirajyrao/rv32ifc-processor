# Vendored arithmetic dependency

Berkeley HardFloat Release 1, John R. Hauser, 2019-07-29.

Source archive: https://www.jhauser.us/arithmetic/HardFloat-1.zip

Downloaded 2026-10-30; SHA-256:
`6b3757c9fbfa2230c6a2b84605e39372cb589dd7500e979c4f0b8ecc8a03b14b`

This directory contains the original `source/*.v`, `source/*.vi` and the
`source/RISCV/HardFloat_specialize.v` / `.vi` specialization, flattened into one
include directory. Local compatibility change: the redundant ANSI output-net redeclaration of sqrtOpOut in divSqrtRecFN_small.v was removed. Arithmetic logic is unchanged. The package license is retained
in COPYING.txt and in the individual source-file headers. This provenance
note accompanies the dependency. Custom integration and derived pipeline wrappers are in ../../rtl/ and retain applicable notices.

