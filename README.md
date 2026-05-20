# Ethan's C Compiler (ECC)

## Introduction

This repository contains Ethan's C Compiler (ECC), a (mostly) functional C compiler written (entirely) in Swift. It was developed using Nora Sandler's [_Writing a C Compiler_](https://nostarch.com/writing-c-compiler), which is a wonderful step-by-step guide to building a C compiler from scratch using the language of your choosing.

## Disclaimers

* This project does not implement a preprocessor or linker and uses gcc for those purposes
* This compiler supports (at present) only x86_64 on macOS

## To Do

### C Language Features (and Extensions)

- [ ] unions
- [ ] typedefs
- [ ] function pointers
- [ ] vector types

### Optimizations (Part III of the Book, and Beyond)

- [ ] Chapter 19 - Machine Independent Optimizations (constant folding, dead code elimination, copy propagation, dead store elimination)
- [ ] Chapter 20 - Machine Dependent Optimizations (register allocation)
- [ ] Auto-vectorization

### Portability

- [ ] ARM backend (probably targeting Apple Silicon)
- [ ] LLVM backend
- [ ] Linux support

### Validation/Verification

 - [ ] (Better) suite of automated regression testing
 - [ ] Medium-large scale project supported by ECC

## Non-Goals

* Self hosting
* Full C-pick-your-favorite-year implementation
* Custom linker/preprocessor