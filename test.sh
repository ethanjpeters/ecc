#!/bin/bash

swift run ecc TestSources/polyparam.c
./polyparam
if [[ $? -ne 78 ]]; then
    echo "polyparam: Expected exit code 78 but got $?"
    exit 1
else
    echo "polyparam: success"
fi
rm polyparam

swift run ecc TestSources/fib.c
./fib
if [[ $? -ne 21 ]]; then
    echo "fib: Expected exit code 21 but got $?"
    exit 1
else
    echo "fib: success"
fi
rm fib

swift run ecc TestSources/multiple_functions.c
./multiple_functions
if [[ $? -ne 3 ]]; then
    echo "multiple_functions: Expected exit code 3 but got $?"
    exit 1
else
    echo "multiple_functions: success"
fi
rm multiple_functions

swift run ecc TestSources/switch.c
./switch
if [[ $? -ne 21 ]]; then
    echo "switch: Expected exit code 21 but got $?"
    exit 1
else
    echo "switch: success"
fi
rm switch

swift run ecc TestSources/loops.c
./loops
if [[ $? -ne 93 ]]; then
    echo "loops: Expected exit code 93 but got $?"
    exit 1
else
    echo "loops: success"
fi
rm loops

swift run ecc TestSources/dup_var.c
./dup_var
if [[ $? -ne 5 ]]; then
    echo "dup_var: Expected exit code 5 but got $?"
    exit 1
else
    echo "dup_var: success"
fi
rm dup_var

swift run ecc TestSources/blocks.c
./blocks
if [[ $? -ne 27 ]]; then
    echo "blocks: Expected exit code 27 but got $?"
    exit 1
else
    echo "blocks: success"
fi
rm blocks

swift run ecc TestSources/control_flow.c
./control_flow
if [[ $? -ne 205 ]]; then
    echo "control_flow: Expected exit code 205 but got $?"
    exit 1
else
    echo "control_flow: success"
fi
rm control_flow

swift run ecc TestSources/increment_decrement.c
./increment_decrement
if [[ $? -ne 3 ]]; then
    echo "increment_decrement: Expected exit code 3 but got $?"
    exit 1
else
    echo "increment_decrement: success"
fi
rm increment_decrement

swift run ecc TestSources/assignment.c
./assignment
if [[ $? -ne 11 ]]; then
    echo "assignment: Expected exit code 11 but got $?"
    exit 1
else
    echo "assignment: success"
fi
rm assignment

swift run ecc TestSources/logical_ops.c
./logical_ops
if [[ $? -ne 0 ]]; then
    echo "logical_ops: Expected exit code 0 but got $?"
    exit 1
else
    echo "logical_ops: success"
fi
rm logical_ops

swift run ecc TestSources/return_2.c
./return_2
if [[ $? -ne 2 ]]; then
    echo "return_2: Expected exit code 2 but got $?"
    exit 1
else
    echo "return_2: success"
fi
rm return_2

swift run ecc TestSources/return_math.c
./return_math
if [[ $? -ne 10 ]]; then
    echo "return_math: Expected exit code 10 but got $?"
    exit 1
else
    echo "return_math: success"
fi
rm return_math

swift run ecc TestSources/return_math_2.c
./return_math_2
if [[ $? -ne 12 ]]; then
    echo "return_math_2: Expected exit code 12 but got $?"
    exit 1
else
    echo "return_math_2: success"
fi
rm return_math_2

swift run ecc TestSources/return_not_2.c
./return_not_2
if [[ $? -ne 1 ]]; then
    echo "return_not_2: Expected exit code 1 but got $?"
    exit 1
else
    echo "return_not_2: success"
fi
rm return_not_2

swift run ecc TestSources/bitwise_ops.c
./bitwise_ops
if [[ $? -ne 7 ]]; then
    echo "bitwise_ops: Expected exit code 7 but got $?"
    exit 1
else
    echo "bitwise_ops: success"
fi
rm bitwise_ops